import Foundation
import AppKit
import Combine
import DiskArbitration

/// Globale soort van een aangekoppeld volume — bepaalt o.a. of een snelle 1-klik
/// offload (SD-kaartje) of de volledige wizard (grote schijf/server) passend is.
enum VolumeKind: String {
    case sdCard          // kaartje uit camera/lezer — geschikt voor 1-klik offload
    case externalDrive   // externe SSD/HDD — bewust de volledige wizard
    case networkVolume   // netwerk/server-share
    case unknown

    var isQuickOffloadEligible: Bool { self == .sdCard }
}

struct ExternalVolume: Identifiable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    let totalSize: Int64
    let freeSpace: Int64
    let isEjectable: Bool
    var kind: VolumeKind = .unknown
    /// Leesbare interface/kabel-aanduiding ("USB", "Thunderbolt", "SD-kaart", "Netwerk").
    var transport: String? = nil

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var formattedFreeSpace: String {
        ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
    }

    var usedPercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(totalSize - freeSpace) / Double(totalSize)
    }
}

class VolumeDetector: ObservableObject {
    static let shared = VolumeDetector()

    @Published var externalVolumes: [ExternalVolume] = []

    /// Publiceert wanneer een nieuw volume wordt aangekoppeld (voor auto-popup)
    let newVolumeDidMount = PassthroughSubject<ExternalVolume, Never>()

    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    init() {}

    func startMonitoring() {
        refreshVolumesAsync()

        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let previousURLs = Set(self.externalVolumes.map { $0.url })
            // Off-main enumereren: een stale netwerkmount mag de UI niet bevriezen
            self.refreshVolumesAsync {
                for volume in self.externalVolumes {
                    if !previousURLs.contains(volume.url) {
                        self.newVolumeDidMount.send(volume)
                    }
                }
            }
        }

        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVolumesAsync()
        }
    }

    func stopMonitoring() {
        if let observer = mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            mountObserver = nil
        }
        if let observer = unmountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            unmountObserver = nil
        }
    }

    /// Ververs de volumelijst zonder de UI te blokkeren.
    /// De enumeratie (mountedVolumeURLs + resourceValues + DiskArbitration) kan seconden
    /// tot minuten hangen op een stale netwerkmount; die draait daarom op de achtergrond
    /// en alleen het eindresultaat wordt op de main thread gepubliceerd.
    func refreshVolumesAsync(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let volumes = self.enumerateVolumes()
            DispatchQueue.main.async {
                self.externalVolumes = volumes
                completion?()
            }
        }
    }

    func refreshVolumes() {
        externalVolumes = enumerateVolumes()
    }

    private func enumerateVolumes() -> [ExternalVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]

        guard let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        return volumeURLs.compactMap { url in
            guard let resources = try? url.resourceValues(forKeys: Set(keys)) else { return nil }

            let isRemovable = resources.volumeIsRemovable ?? false
            let isEjectable = resources.volumeIsEjectable ?? false
            let isInternal = resources.volumeIsInternal ?? false
            let isOnVolumes = url.path.hasPrefix("/Volumes/")

            // Interne volumes alleen toestaan als ze removable/ejectable zijn
            // (bijv. SD-kaart via ingebouwde kaartlezer)
            if isInternal && !isRemovable && !isEjectable { return nil }

            // Niet-interne volumes: toestaan als removable/ejectable OF gemount in /Volumes/
            // (sommige USB card readers rapporteren Fixed + niet-ejectable)
            if !isInternal && !isRemovable && !isEjectable && !isOnVolumes { return nil }

            let name = resources.volumeName ?? url.lastPathComponent

            // Filter systeem-volumes
            let lowName = name.lowercased()
            if lowName.contains("time machine") || lowName == "recovery" || lowName == "preboot" {
                return nil
            }

            let totalSize = Int64(resources.volumeTotalCapacity ?? 0)
            let freeSpace = Int64(resources.volumeAvailableCapacity ?? 0)

            let classification = self.classifyVolume(url: url, totalSize: totalSize, isEjectable: isEjectable)

            return ExternalVolume(
                id: UUID(),
                name: name,
                url: url,
                totalSize: totalSize,
                freeSpace: freeSpace,
                isEjectable: isEjectable,
                kind: classification.kind,
                transport: classification.transport
            )
        }
    }

    /// Classificeer een volume op soort + interface via DiskArbitration (snel, geen subprocess).
    private func classifyVolume(url: URL, totalSize: Int64, isEjectable: Bool) -> (kind: VolumeKind, transport: String?) {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let desc = DADiskCopyDescription(disk) as? [String: Any] else {
            return (.unknown, nil)
        }

        // Netwerk/server-share?
        if (desc[kDADiskDescriptionVolumeNetworkKey as String] as? Bool) == true {
            return (.networkVolume, "Netwerk")
        }

        let proto = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let model = ((desc[kDADiskDescriptionDeviceModelKey as String] as? String) ?? "").lowercased()
        let mediaName = ((desc[kDADiskDescriptionMediaNameKey as String] as? String) ?? "").lowercased()

        // Leesbare interface-aanduiding voor de "what the cable"-badge
        let transport: String?
        switch proto {
        case "Secure Digital":              transport = "SD-kaart"
        case "USB":                         transport = "USB"
        case "Thunderbolt":                 transport = "Thunderbolt"
        case "SATA", "Serial ATA":          transport = "SATA"
        case "PCI-Express", "Apple Fabric": transport = "Intern"
        default:                            transport = proto
        }

        // SD-/kaart-detectie: protocol, model/medianaam, of klein verwijderbaar USB-volume.
        let cardKeywords = ["secure digital", "sdhc", "sdxc", "card reader", "cardreader", "cfexpress", "compactflash"]
        let looksLikeCard = proto == "Secure Digital"
            || cardKeywords.contains(where: { model.contains($0) || mediaName.contains($0) })
        let smallRemovable = isEjectable && totalSize > 0 && totalSize < 256 * 1024 * 1024 * 1024 // < ~256 GB

        if looksLikeCard || (smallRemovable && proto == "USB") {
            return (.sdCard, transport)
        }
        return (.externalDrive, transport)
    }

    func ejectVolume(_ volume: ExternalVolume) {
        ejectVolume(at: volume.url)
    }

    /// Werp een volume uit en meld het resultaat. Een mislukte eject (bestanden nog in
    /// gebruik) werd voorheen stil geslikt — de gebruiker trok de kaart eruit terwijl
    /// die nog gemount was, met corruptierisico.
    func ejectVolume(at url: URL) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Kan volume niet uitwerpen"
            alert.informativeText = "\(url.lastPathComponent) is nog in gebruik.\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    deinit {
        stopMonitoring()
    }
}
