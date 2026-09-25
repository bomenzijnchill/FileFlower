import SwiftUI
import AppKit

/// Eenmalig bevestigings-paneel per project: toont de gedetecteerde mapindeling
/// (asset-type → map), bewerkbaar per rij. De gebruiker hoeft meestal alleen "Akkoord"
/// te klikken; daarna is de mapping gezaghebbend (confidence 1.0) en stuurt hij alle plaatsing.
struct ProjectMappingConfirmationSheet: View {
    let project: ProjectInfo
    /// Aangeroepen NA opslaan van de bevestigde mapping.
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var rows: [ProposedFolderMapping] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "mapping.confirm.title"))
                    .font(.system(size: 15, weight: .semibold))
                Text(project.name)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(String(localized: "mapping.confirm.subtitle"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "mapping.confirm.detecting"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($rows) { $row in
                            ConfirmRow(project: project, row: $row)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            HStack {
                Button(String(localized: "mapping.confirm.redetect")) {
                    Task { await load() }
                }
                .controlSize(.small)
                .disabled(isLoading)

                Spacer()

                Button(String(localized: "common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "mapping.confirm.apply")) {
                    applyAndConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        rows = await ProjectStructureDetector.shared.detect(for: project)
        isLoading = false
    }

    private func applyAndConfirm() {
        // 1) Bewaar elke (niet-lege) rij als gezaghebbende handmatige regel.
        for row in rows where !row.relativePath.isEmpty {
            PathLearningManager.shared.recordPathDecision(
                projectPath: project.projectPath,
                assetType: row.assetType,
                subfolder: nil,
                chosenPath: row.relativePath,
                fileExtension: "",
                source: nil,
                isScanned: false
            )
        }

        // 2) Markeer de mapping als bevestigd + persisteer.
        var config = AppState.shared.config
        var mapping = config.mappings[project.projectPath] ?? ProjectMapping()
        var structure = mapping.discoveredStructure ?? DiscoveredProjectStructure(
            discoveredPaths: [:],
            namingConvention: nil,
            lastScannedDate: Date()
        )
        structure.confirmed = true
        structure.confirmedAt = Date()
        mapping.discoveredStructure = structure
        config.mappings[project.projectPath] = mapping
        AppState.shared.config = config
        ConfigManager.shared.save(config)

        onConfirm()
    }
}

/// Eén bewerkbare rij: asset-type + voorgestelde map + route-preview + bron-badge.
private struct ConfirmRow: View {
    let project: ProjectInfo
    @Binding var row: ProposedFolderMapping

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForType(row.assetType))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.assetType.displayName)
                        .font(.system(size: 12, weight: .medium))
                    sourceBadge
                }
                Text("\(project.name) → \(row.relativePath.isEmpty ? "—" : row.relativePath)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(row.relativePath.isEmpty ? .orange : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(String(localized: "mapping.confirm.change")) { chooseFolder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch row.source {
        case .scan:
            badge(text: "✓ \(row.scanFileCount)", color: .green)
        case .ai:
            badge(text: "AI", color: .blue)
        case .keyword:
            badge(text: "≈", color: .secondary)
        case .none:
            badge(text: "?", color: .orange)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func chooseFolder() {
        // Voorkom dat de transient popover sluit terwijl de folder picker open is
        StatusBarController.shared.setPopoverBehavior(.applicationDefined)
        defer { StatusBarController.shared.setPopoverBehavior(.transient) }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = PathResolver.shared.projectMainFolderURL(for: project)
        if panel.runModal() == .OK, let url = panel.url {
            if let rel = PathResolver.shared.makeRelativeToProject(url.path, project: project) {
                row.relativePath = rel
                row.source = .none // handmatig gekozen
            }
        }
    }
}
