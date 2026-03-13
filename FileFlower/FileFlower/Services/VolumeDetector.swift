import Foundation
import AppKit
import Combine

struct ExternalVolume: Identifiable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    let totalSize: Int64
    let freeSpace: Int64
    let isEjectable: Bool

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
        refreshVolumes()

        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let previousURLs = Set(self.externalVolumes.map { $0.url })
            self.refreshVolumes()
            // Publiceer nieuw toegevoegde volumes
            for volume in self.externalVolumes {
                if !previousURLs.contains(volume.url) {
                    self.newVolumeDidMount.send(volume)
                }
            }
        }

        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVolumes()
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

    func refreshVolumes() {
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
            externalVolumes = []
            return
        }

        externalVolumes = volumeURLs.compactMap { url in
            guard let resources = try? url.resourceValues(forKeys: Set(keys)) else { return nil }

            // Filter interne volumes
            if resources.volumeIsInternal == true { return nil }

            // Moet verwijderbaar of uitwerpbaar zijn
            let isRemovable = resources.volumeIsRemovable ?? false
            let isEjectable = resources.volumeIsEjectable ?? false
            guard isRemovable || isEjectable else { return nil }

            let name = resources.volumeName ?? url.lastPathComponent

            // Filter systeem-volumes
            let lowName = name.lowercased()
            if lowName.contains("time machine") || lowName == "recovery" || lowName == "preboot" {
                return nil
            }

            let totalSize = Int64(resources.volumeTotalCapacity ?? 0)
            let freeSpace = Int64(resources.volumeAvailableCapacity ?? 0)

            return ExternalVolume(
                id: UUID(),
                name: name,
                url: url,
                totalSize: totalSize,
                freeSpace: freeSpace,
                isEjectable: isEjectable
            )
        }
    }

    func ejectVolume(_ volume: ExternalVolume) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
    }

    deinit {
        stopMonitoring()
    }
}
