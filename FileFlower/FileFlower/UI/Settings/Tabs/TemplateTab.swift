import SwiftUI
import UniformTypeIdentifiers

struct TemplateTabView: View {
    @ObservedObject var appState: AppState
    @Binding var folderStructurePreset: FolderStructurePreset
    let onSave: () -> Void

    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument: TemplateExportDocument?
    @State private var importError: String?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var presetTree: [String] {
        switch folderStructurePreset {
        case .standard:
            return ["00_Project", "01_Footage", "02_Audio", "03_Music", "04_VO_SFX", "05_Graphics_Exports"]
        case .flat:
            return ["Footage", "Audio", "Graphics", "Exports"]
        case .custom:
            return ["00_Custom"]
        }
    }

    private var presetMeta: [(preset: FolderStructurePreset, name: String, desc: String)] {
        [
            (.standard, String(localized: "settings.preset.standard"), String(localized: "settings.preset.standard.desc")),
            (.flat,     String(localized: "settings.preset.flat"),     String(localized: "settings.preset.flat.desc")),
            (.custom,   String(localized: "settings.preset.custom"),   String(localized: "settings.preset.custom.desc"))
        ]
    }

    private var customTemplates: [FolderStructureTemplate] {
        appState.config.folderTemplates
    }

    private var activeCustomTemplateId: UUID? {
        appState.config.defaultTemplateId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preset grid
            SettingsCard(
                title: String(localized: "settings.card.preset"),
                desc: String(localized: "settings.card.preset.desc")
            ) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(presetMeta, id: \.preset) { item in
                        PresetCard(
                            name: item.name,
                            meta: item.desc,
                            isActive: folderStructurePreset == item.preset && activeCustomTemplateId == nil
                        ) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                folderStructurePreset = item.preset
                                appState.config.defaultTemplateId = nil
                            }
                            onSave()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Preview
            SettingsCard(
                title: String(localized: "settings.card.preview"),
                desc: String(format: String(localized: "settings.card.preview.desc %@"), currentActiveName)
            ) {
                TreePreview(
                    rootName: "Mijn_Project_2026",
                    entries: previewEntries
                )
                .id("\(folderStructurePreset)-\(activeCustomTemplateId?.uuidString ?? "")")
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .padding(.vertical, 4)
            }

            // Custom templates
            if !customTemplates.isEmpty {
                SettingsCard(
                    title: String(localized: "settings.card.custom_templates"),
                    desc: String(localized: "settings.card.custom_templates.desc")
                ) {
                    VStack(spacing: 0) {
                        ForEach(Array(customTemplates.enumerated()), id: \.element.id) { index, template in
                            customTemplateRow(template, isFirst: index == 0)
                        }
                    }
                }
            }

            // Editor
            SettingsCard(
                title: String(localized: "settings.card.template_editor"),
                desc: String(localized: "settings.card.template_editor.desc"),
                kicker: String(localized: "settings.kicker.advanced")
            ) {
                SettingsRow(
                    label: String(localized: "settings.template.open_editor"),
                    help: String(localized: "settings.template.open_editor.help"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.template.open_editor.button") + " →",
                                variant: .primary,
                                size: .regular) {
                        TemplateEditorWindowController.show()
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.template.import_export"),
                    help: String(localized: "settings.template.import_export.help")
                ) {
                    HStack(spacing: 6) {
                        BrandButton(title: String(localized: "settings.template.import") + "…",
                                    variant: .secondary, size: .regular) {
                            showImporter = true
                        }
                        BrandButton(title: String(localized: "settings.template.export"),
                                    variant: .secondary, size: .regular) {
                            triggerExport()
                        }
                        .disabled(customTemplates.isEmpty && exportableActive == nil)
                    }
                }

                if let error = importError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.statusBad)
                        .padding(.top, 4)
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename
        ) { result in
            if case .failure(let err) = result {
                importError = err.localizedDescription
            }
        }
    }

    // MARK: - Custom template row

    @ViewBuilder
    private func customTemplateRow(_ template: FolderStructureTemplate, isFirst: Bool) -> some View {
        VStack(spacing: 0) {
            if !isFirst {
                Divider().background(Color.line)
            }
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12))
                    .foregroundColor(activeCustomTemplateId == template.id ? .brandBurntPeach : .ink3)
                    .frame(width: 22, height: 22)
                    .background(
                        activeCustomTemplateId == template.id
                            ? Color.brandBurntPeach.opacity(0.12)
                            : Color.black.opacity(0.04)
                    )
                    .cornerRadius(5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.ink)
                    Text(templateMeta(template))
                        .font(.system(size: 11))
                        .foregroundColor(.ink3)
                }

                Spacer()

                if activeCustomTemplateId == template.id {
                    Text(String(localized: "settings.template.active_badge").uppercased())
                        .font(.brandMono(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(.peach3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brandBurntPeach.opacity(0.12))
                        .cornerRadius(4)
                } else {
                    BrandButton(title: String(localized: "settings.template.set_active"),
                                variant: .ghost, size: .tiny) {
                        appState.config.defaultTemplateId = template.id
                        onSave()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func templateMeta(_ template: FolderStructureTemplate) -> String {
        let count = template.folderTree.children.count
        let folderWord = count == 1
            ? String(localized: "settings.template.folder_word")
            : String(localized: "settings.template.folders_word")
        return "\(count) \(folderWord)"
    }

    // MARK: - Preview helpers

    private var previewEntries: [String] {
        if let id = activeCustomTemplateId,
           let template = customTemplates.first(where: { $0.id == id }) {
            return template.folderTree.children.map { $0.name }
        }
        return presetTree
    }

    private var currentActiveName: String {
        if let id = activeCustomTemplateId,
           let template = customTemplates.first(where: { $0.id == id }) {
            return template.name
        }
        return presetMeta.first(where: { $0.preset == folderStructurePreset })?.name ?? "Standaard"
    }

    // MARK: - Import / Export

    private var exportableActive: FolderStructureTemplate? {
        if let id = activeCustomTemplateId {
            return customTemplates.first(where: { $0.id == id })
        }
        return customTemplates.first
    }

    private var defaultExportFilename: String {
        let name = exportableActive?.name ?? "FileFlower-Template"
        return name.replacingOccurrences(of: "/", with: "-") + ".json"
    }

    private func triggerExport() {
        guard let template = exportableActive else {
            importError = String(localized: "settings.template.export_no_template")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(template)
            exportDocument = TemplateExportDocument(data: data)
            importError = nil
            showExporter = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard case .success(let urls) = result, let url = urls.first else { return }
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(FolderStructureTemplate.self, from: data)

            // Geef de geïmporteerde template een nieuwe UUID om collisions te voorkomen
            let imported = FolderStructureTemplate(
                id: UUID(),
                name: decoded.name + " " + String(localized: "settings.template.imported_suffix"),
                folderTree: decoded.folderTree,
                parameters: decoded.parameters,
                mapping: decoded.mapping,
                sourcePath: decoded.sourcePath,
                createdAt: Date(),
                lastUpdatedAt: Date()
            )

            appState.config.folderTemplates.append(imported)
            onSave()
            importError = nil
        } catch {
            importError = String(format: String(localized: "settings.template.import_failed %@"),
                                 error.localizedDescription)
        }
    }
}

// MARK: - Export document

struct TemplateExportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    static var writableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
