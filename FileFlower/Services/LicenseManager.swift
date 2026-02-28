import Foundation
import AppKit
import Combine
import CryptoKit
import IOKit

/// Beheert Gumroad license key validatie en activering
class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: - Published Properties

    @Published var isLicensed = false
    @Published var isValidating = false
    @Published var licenseError: String?
    @Published var licenseInfo: LicenseInfo?

    // MARK: - Configuration

    /// Geobfusceerd product ID — wordt bij runtime gedecodeerd
    private var productId: String {
        // XOR-geobfusceerde bytes van het product ID
        let obfuscated: [UInt8] = [0x22, 0x18, 0x30, 0x40, 0x1f, 0x12, 0x16, 0x1a, 0x39, 0x3e, 0x07, 0x11, 0x3c, 0x32, 0x45, 0x0b, 0x25, 0x09, 0x30, 0x46, 0x2b, 0x04, 0x4e, 0x4e]
        let xorKey: UInt8 = 0x73
        let decoded = obfuscated.map { $0 ^ xorKey }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    /// Gumroad API endpoint
    private let gumroadAPIURL = "https://api.gumroad.com/v2/licenses/verify"

    // MARK: - Storage Keys

    private let licenseKeyStorageKey = "gumroad_license_key"
    private let licenseInfoStorageKey = "gumroad_license_info"
    private let lastValidationKey = "license_last_validation"

    // MARK: - Trial Configuration

    /// Aantal dagen voor trial periode (0 = geen trial)
    private let trialDays = 7
    private let trialStartKey = "trial_start_date"
    private let trialStartKeychainKey = "trial_start_timestamp"
    private let trialHashKey = "trial_integrity_hash"
    private let lastSeenDateKey = "trial_last_seen"
    private let trialInitializedKey = "trial_initialized"

    /// Geobfusceerde salt voor trial integrity hash — niet triviaal afleidbaar
    private var trialSalt: String {
        let obfuscated: [UInt8] = [0x36, 0x1c, 0x07, 0x30, 0x55, 0x08, 0x32, 0x4a, 0x17, 0x09, 0x3b, 0x42, 0x15, 0x01, 0x34, 0x56]
        let xorKey: UInt8 = 0x65
        let decoded = obfuscated.map { $0 ^ xorKey }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }
    
    // MARK: - Initialization
    
    private init() {
        migrateTrialDateToKeychain()
        updateLastSeenDate()
        loadStoredLicense()
    }
    
    // MARK: - Public Properties
    
    /// De opgeslagen license key
    var storedLicenseKey: String? {
        get { 
            // Gebruik Keychain voor veilige opslag
            KeychainHelper.load(key: licenseKeyStorageKey)
        }
        set {
            if let key = newValue {
                KeychainHelper.save(key: licenseKeyStorageKey, value: key)
            } else {
                KeychainHelper.delete(key: licenseKeyStorageKey)
            }
        }
    }
    
    /// Check of de gebruiker in trial mode zit
    var isInTrial: Bool {
        guard trialDays > 0 else { return false }
        guard !isLicensed else { return false }

        // Anti-tamper: als trial ooit is gestart maar Keychain data ontbreekt → tampering
        let trialEverStarted = UserDefaults.standard.bool(forKey: trialInitializedKey)

        if let startDate = loadTrialStartDate() {
            // Verificeer integriteit van trial startdatum
            guard verifyTrialIntegrity(startDate) else {
                return false
            }
            // Klok-terugzet detectie
            if let lastSeen = loadLastSeenDate(), Date() < lastSeen {
                return false
            }
            let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
            return daysSinceStart >= 0 && daysSinceStart < trialDays
        } else if trialEverStarted {
            // Keychain is gewist maar trial was al gestart → tampering
            return false
        } else {
            // Start trial
            let now = Date()
            saveTrialStartDate(now)
            UserDefaults.standard.set(true, forKey: trialInitializedKey)
            saveTrialIntegrityHash(now)
            return true
        }
    }
    
    /// Dagen over in trial
    var trialDaysRemaining: Int {
        guard trialDays > 0, !isLicensed else { return 0 }

        if let startDate = loadTrialStartDate() {
            let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
            return max(0, trialDays - daysSinceStart)
        }
        return trialDays
    }
    
    /// Check of de app mag worden gebruikt (licensed of in trial)
    var canUseApp: Bool {
        return isLicensed || isInTrial
    }
    
    // MARK: - License Validation
    
    /// Valideer en activeer een license key
    func activateLicense(key: String) async -> Result<LicenseInfo, LicenseError> {
        await MainActor.run {
            isValidating = true
            licenseError = nil
        }
        
        defer {
            Task { @MainActor in
                isValidating = false
            }
        }
        
        // Validate via Gumroad API
        guard let url = URL(string: gumroadAPIURL) else {
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "product_id=\(productId)&license_key=\(key)"
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Parse response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.parseError)
            }
            
            let success = json["success"] as? Bool ?? false
            
            if success {
                // Extract license info
                let purchase = json["purchase"] as? [String: Any] ?? [:]
                let email = purchase["email"] as? String ?? ""
                let createdAt = purchase["created_at"] as? String ?? ""
                let refunded = purchase["refunded"] as? Bool ?? false
                let disputed = purchase["disputed"] as? Bool ?? false
                let chargebacked = purchase["chargebacked"] as? Bool ?? false
                let uses = json["uses"] as? Int ?? 0
                
                // Check if license is still valid (not refunded/disputed)
                if refunded || disputed || chargebacked {
                    return .failure(.licenseRevoked)
                }
                
                let info = LicenseInfo(
                    licenseKey: key,
                    email: email,
                    purchaseDate: createdAt,
                    uses: uses,
                    validatedAt: Date()
                )
                
                // Store license
                await MainActor.run {
                    self.storedLicenseKey = key
                    self.licenseInfo = info
                    self.isLicensed = true
                    self.saveLicenseInfo(info)
                }
                
                #if DEBUG
                print("LicenseManager: License geactiveerd")
                #endif
                return .success(info)
                
            } else {
                let message = json["message"] as? String ?? "Ongeldige license key"
                return .failure(.invalidKey(message))
            }
            
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    /// Deactiveer de huidige license
    func deactivateLicense() {
        storedLicenseKey = nil
        licenseInfo = nil
        isLicensed = false
        KeychainHelper.delete(key: licenseInfoStorageKey)
        UserDefaults.standard.removeObject(forKey: licenseInfoStorageKey)
        UserDefaults.standard.removeObject(forKey: lastValidationKey)
    }
    
    /// Hervalideer de opgeslagen license (bij app start)
    func revalidateStoredLicense() async {
        guard let key = storedLicenseKey else {
            await MainActor.run {
                isLicensed = false
            }
            return
        }
        
        // Check of we recent hebben gevalideerd (binnen 24 uur)
        if let lastValidation = UserDefaults.standard.object(forKey: lastValidationKey) as? Date {
            let hoursSinceValidation = Date().timeIntervalSince(lastValidation) / 3600
            if hoursSinceValidation < 24 {
                // Gebruik cached license info
                if let info = loadLicenseInfo() {
                    await MainActor.run {
                        self.licenseInfo = info
                        self.isLicensed = true
                    }
                    return
                }
            }
        }
        
        // Valideer opnieuw
        let result = await activateLicense(key: key)
        
        switch result {
        case .success:
            UserDefaults.standard.set(Date(), forKey: lastValidationKey)
        case .failure(let error):
            await MainActor.run {
                self.licenseError = error.localizedDescription
                // Bij netwerk errors, behoud de license (offline gebruik)
                if case .networkError = error {
                    if let info = self.loadLicenseInfo() {
                        self.licenseInfo = info
                        self.isLicensed = true
                    }
                } else {
                    // License is ongeldig geworden
                    self.deactivateLicense()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadStoredLicense() {
        if let info = loadLicenseInfo(), storedLicenseKey != nil {
            licenseInfo = info
            isLicensed = true
        }
    }
    
    private func saveLicenseInfo(_ info: LicenseInfo) {
        if let data = try? JSONEncoder().encode(info),
           let jsonString = String(data: data, encoding: .utf8) {
            KeychainHelper.save(key: licenseInfoStorageKey, value: jsonString)
        }
    }

    private func loadLicenseInfo() -> LicenseInfo? {
        // Migreer van UserDefaults naar Keychain indien nodig
        if let legacyData = UserDefaults.standard.data(forKey: licenseInfoStorageKey) {
            if let info = try? JSONDecoder().decode(LicenseInfo.self, from: legacyData) {
                saveLicenseInfo(info)
                UserDefaults.standard.removeObject(forKey: licenseInfoStorageKey)
                return info
            }
        }
        guard let jsonString = KeychainHelper.load(key: licenseInfoStorageKey),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(LicenseInfo.self, from: data)
    }

    // MARK: - Trial Date Storage (Keychain)

    private func saveTrialStartDate(_ date: Date) {
        let timestamp = String(Int(date.timeIntervalSince1970))
        KeychainHelper.save(key: trialStartKeychainKey, value: timestamp)
    }

    private func loadTrialStartDate() -> Date? {
        guard let timestampStr = KeychainHelper.load(key: trialStartKeychainKey),
              let timestamp = TimeInterval(timestampStr) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Eenmalige migratie van UserDefaults trial datum naar Keychain
    private func migrateTrialDateToKeychain() {
        if let legacyDate = UserDefaults.standard.object(forKey: trialStartKey) as? Date {
            if loadTrialStartDate() == nil {
                saveTrialStartDate(legacyDate)
                if !UserDefaults.standard.bool(forKey: trialInitializedKey) {
                    UserDefaults.standard.set(true, forKey: trialInitializedKey)
                }
            }
            UserDefaults.standard.removeObject(forKey: trialStartKey)
        }
    }

    // MARK: - Clock Rollback Detection

    private func updateLastSeenDate() {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        KeychainHelper.save(key: lastSeenDateKey, value: timestamp)
    }

    private func loadLastSeenDate() -> Date? {
        guard let timestampStr = KeychainHelper.load(key: lastSeenDateKey),
              let timestamp = TimeInterval(timestampStr) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    // MARK: - Trial Integrity

    private func trialIntegrityHash(_ date: Date) -> String {
        let timestamp = String(Int(date.timeIntervalSince1970))
        let hwUUID = hardwareUUID() ?? "unknown"
        let input = Data((timestamp + trialSalt + hwUUID).utf8)
        let hash = SHA256.hash(data: input)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func saveTrialIntegrityHash(_ date: Date) {
        let hash = trialIntegrityHash(date)
        KeychainHelper.save(key: trialHashKey, value: hash)
    }

    private func verifyTrialIntegrity(_ date: Date) -> Bool {
        guard let storedHash = KeychainHelper.load(key: trialHashKey) else {
            return false
        }
        return storedHash == trialIntegrityHash(date)
    }

    // MARK: - Hardware UUID

    private func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let key = kIOPlatformUUIDKey as CFString
        guard let uuid = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }
        return uuid
    }
}

// MARK: - Supporting Types

struct LicenseInfo: Codable {
    let licenseKey: String
    let email: String
    let purchaseDate: String
    let uses: Int
    let validatedAt: Date
    
    /// Gemaskeerde license key voor weergave
    var maskedKey: String {
        guard licenseKey.count > 8 else { return licenseKey }
        let prefix = String(licenseKey.prefix(4))
        let suffix = String(licenseKey.suffix(4))
        return "\(prefix)****\(suffix)"
    }
}

enum LicenseError: LocalizedError {
    case invalidURL
    case networkError(String)
    case parseError
    case invalidKey(String)
    case licenseRevoked
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ongeldige API URL"
        case .networkError(let message):
            return "Netwerkfout: \(message)"
        case .parseError:
            return "Kon response niet verwerken"
        case .invalidKey(let message):
            return message
        case .licenseRevoked:
            return "Deze license is geannuleerd of terugbetaald"
        }
    }
}

// MARK: - Keychain Helper

/// Veilige opslag van license key in Keychain
struct KeychainHelper {
    private static let service = "com.koendijkstra.FileFlower"

    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Verwijder bestaande item
        SecItemDelete(query as CFDictionary)

        // Voeg nieuwe toe
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            // Fallback: probeer zonder service (migratie van oude entries)
            return loadLegacy(key: key)
        }

        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        // Verwijder ook eventuele legacy entries zonder service
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }

    /// Migratie: lees oude entries zonder kSecAttrService en heropsla met service
    private static func loadLegacy(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Migreer naar nieuwe format met service
        save(key: key, value: value)
        // Verwijder oude entry zonder service
        SecItemDelete(query as CFDictionary)

        return value
    }
}

