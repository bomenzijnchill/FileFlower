import Foundation

class ThermalManager {
    static let shared = ThermalManager()

    private let checkInterval: TimeInterval = 2.0
    private var lastCheckTime: Date = Date()
    private var isThrottling: Bool = false

    private init() {}

    /// Check of we kunnen verwerken zonder overbelasting
    func canProcess() -> Bool {
        let now = Date()

        // Rate limiting: max 1 classificatie per seconde als we throttlen
        if isThrottling {
            if now.timeIntervalSince(lastCheckTime) < 1.0 {
                return false
            }
        }

        lastCheckTime = now
        return true
    }

    /// Wacht tot we kunnen verwerken (met timeout)
    func waitUntilCanProcess(timeout: TimeInterval = 10.0) async -> Bool {
        let startTime = Date()

        while !canProcess() {
            if Date().timeIntervalSince(startTime) > timeout {
                return false
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return true
    }

    /// Reset throttling status
    func reset() {
        isThrottling = false
        lastCheckTime = Date()
    }

    /// Check of we momenteel throttlen
    var isCurrentlyThrottling: Bool {
        return isThrottling
    }
}
