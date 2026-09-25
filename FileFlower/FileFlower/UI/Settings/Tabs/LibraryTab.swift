import SwiftUI

struct LibraryTabView: View {
    @Binding var projectRoots: [String]
    @Binding var newRoot: String
    @Binding var downloadsFolder: String
    let onSave: () -> Void

    @State private var rootAccessibility: [String: Bool] = [:]
    @State private var rootProjectCounts: [String: Int] = [:]
    @State private var rootScannedAt: [String: Date] = [:]

    private var defaultDownloadsPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Downloads-map
            SettingsCard(
                title: String(localized: "settings.card.downloads_folder"),
                desc: String(localized: "settings.card.downloads_folder.desc")
            ) {
                downloadsFolderRow
            }

            // Project roots
            SettingsCard(
                title: String(localized: "settings.card.project_roots"),
                desc: String(localized: "settings.card.project_roots.desc")
            ) {
                if !projectRoots.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(projectRoots.enumerated()), id: \.element) { index, root in
                            projectRootRow(root, isFirst: index == 0)
                        }
                    }
                }

                addRootRow
                    .padding(.top, 12)
            }
        }
        .task {
            await scanRoots()
        }
        .onChange(of: projectRoots) { _, _ in
            Task { await scanRoots() }
        }
    }

    // MARK: - Downloads folder

    private var downloadsFolderRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.statusOk)
                .frame(width: 8, height: 8)

            HStack(spacing: 4) {
                Text(downloadsFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.brandMono(size: 11.5, weight: .medium))
                    .foregroundColor(.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if downloadsFolder == defaultDownloadsPath {
                Text(String(localized: "settings.downloads_folder.default_badge"))
                    .font(.system(size: 11))
                    .foregroundColor(.ink3)
            }

            BrandButton(title: String(localized: "settings.downloads_folder.change"),
                        variant: .secondary,
                        size: .tiny) {
                browseDownloadsFolder()
            }

            if downloadsFolder != defaultDownloadsPath {
                BrandButton(title: "Reset", variant: .ghost, size: .tiny) {
                    downloadsFolder = defaultDownloadsPath
                    onSave()
                    DispatchQueue.main.async {
                        DownloadsWatcher.shared.updateDownloadsFolder(URL(fileURLWithPath: defaultDownloadsPath))
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Project root row

    private func projectRootRow(_ root: String, isFirst: Bool) -> some View {
        VStack(spacing: 0) {
            if !isFirst {
                Divider().background(Color.line)
            }
            HStack(spacing: 10) {
                Circle()
                    .fill(rootAccessibility[root] == true ? Color.statusOk : Color.statusBad)
                    .frame(width: 8, height: 8)

                Text(root.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.brandMono(size: 11.5, weight: .medium))
                    .foregroundColor(rootAccessibility[root] == true ? .ink : .ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                rootMeta(for: root)

                Button(action: {
                    projectRoots.removeAll { $0 == root }
                    onSave()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ink3)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func rootMeta(for root: String) -> some View {
        HStack(spacing: 4) {
            if rootAccessibility[root] == true, let count = rootProjectCounts[root] {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ink2)
                Text(String(localized: "settings.library.projects_word"))
                    .font(.system(size: 11))
                    .foregroundColor(.ink3)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(.ink4)
                Text(freshness(for: root))
                    .font(.system(size: 11))
                    .foregroundColor(.ink3)
            } else {
                Text(String(localized: "settings.library.offline"))
                    .font(.system(size: 11))
                    .foregroundColor(.statusBad)
            }
        }
    }

    private func freshness(for root: String) -> String {
        guard let scanned = rootScannedAt[root] else { return String(localized: "settings.library.never_scanned") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: scanned, relativeTo: Date())
    }

    // MARK: - Add row

    private var addRootRow: some View {
        HStack(spacing: 6) {
            TextField("/Volumes/…", text: $newRoot)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .font(.brandMono(size: 11.5))

            BrandButton(title: String(localized: "common.browse") + "…",
                        variant: .secondary, size: .regular) {
                browseProjectRoot()
            }

            BrandButton(title: String(localized: "common.add"),
                        icon: "plus",
                        variant: .primary,
                        size: .regular) {
                guard !newRoot.isEmpty, !projectRoots.contains(newRoot) else { return }
                projectRoots.append(newRoot)
                newRoot = ""
                onSave()
                Task { await AppState.shared.refreshRecentProjects() }
            }
            .disabled(newRoot.isEmpty)
        }
    }

    // MARK: - Helpers

    private func browseProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { response in
            DispatchQueue.main.async {
                if response == .OK, let url = panel.url {
                    newRoot = url.path
                }
            }
        }
    }

    private func browseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { response in
            DispatchQueue.main.async {
                if response == .OK, let url = panel.url {
                    downloadsFolder = url.path
                    onSave()
                    DownloadsWatcher.shared.updateDownloadsFolder(url)
                }
            }
        }
    }

    private func scanRoots() async {
        for root in projectRoots {
            let accessible = FileManager.default.isReadableFile(atPath: root)
            await MainActor.run { rootAccessibility[root] = accessible }
        }
        let results = await ProjectScanner.shared.scanRecentProjects(roots: projectRoots, limit: 100)
        var counts: [String: Int] = [:]
        for root in projectRoots {
            counts[root] = results.filter { $0.projectPath.hasPrefix(root) }.count
        }
        let now = Date()
        await MainActor.run {
            rootProjectCounts = counts
            for root in projectRoots {
                rootScannedAt[root] = now
            }
        }
    }
}
