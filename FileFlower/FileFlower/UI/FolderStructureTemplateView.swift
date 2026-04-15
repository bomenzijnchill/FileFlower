import SwiftUI
import AppKit

// MARK: - Main tab view
// Top-level view voor de "Folder Structure"-settings tab.
// Split-layout: linker lijst met templates + presets, rechter editor-pane.

struct FolderStructureTemplateView: View {
    @ObservedObject var appState: AppState
    let folderStructurePreset: Binding<FolderStructurePreset>
    let onSave: () -> Void

    @State private var selectedTemplateId: UUID?
    @State private var showRenamePromptForId: UUID?
    @State private var renameDraft: String = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, minHeight: 480)
        .onAppear {
            if selectedTemplateId == nil {
                selectedTemplateId = appState.config.defaultTemplateId ?? appState.config.folderTemplates.first?.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preset-sectie (legacy presets blijven naast templates bestaan)
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "folder_structure.preset_section"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                Picker("", selection: folderStructurePreset) {
                    ForEach(FolderStructurePreset.allCases, id: \.self) { preset in
                        Text(String(localized: preset.displayKey)).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 10)
                .onChange(of: folderStructurePreset.wrappedValue) { _, _ in onSave() }
            }

            Divider()
                .padding(.top, 10)

            // Template-lijst
            HStack {
                Text(String(localized: "folder_structure.templates"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    Button(String(localized: "folder_structure.create.from_scratch")) {
                        addFromScratch()
                    }
                    Button(String(localized: "folder_structure.create.from_scan")) {
                        addFromScan()
                    }
                    if selectedTemplate != nil {
                        Button(String(localized: "folder_structure.create.from_duplicate")) {
                            duplicateSelected()
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.config.folderTemplates) { template in
                        TemplateSidebarRow(
                            template: template,
                            isSelected: selectedTemplateId == template.id,
                            isDefault: appState.config.defaultTemplateId == template.id,
                            onSelect: { selectedTemplateId = template.id },
                            onSetDefault: { setDefault(template.id) },
                            onDuplicate: { duplicate(template) },
                            onDelete: { delete(template) },
                            onRename: { startRename(template) }
                        )
                    }

                    if appState.config.folderTemplates.isEmpty {
                        Text(String(localized: "folder_structure.empty_list"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let template = selectedTemplate {
            TemplateEditorPane(
                template: template,
                onUpdate: { updated in update(template: updated) },
                onRename: { startRename(template) }
            )
            .id(template.id) // reset state wanneer selectie wijzigt
        } else {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(String(localized: "folder_structure.select_or_create"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Computed

    private var selectedTemplate: FolderStructureTemplate? {
        guard let id = selectedTemplateId else { return nil }
        return appState.config.folderTemplates.first(where: { $0.id == id })
    }

    // MARK: - Actions

    private func addFromScratch() {
        let new = FolderStructureTemplate(
            name: String(localized: "folder_structure.default_name"),
            folderTree: FolderNode(name: "", relativePath: "", children: []),
            parameters: []
        )
        appState.config.folderTemplates.append(new)
        if appState.config.defaultTemplateId == nil {
            appState.config.defaultTemplateId = new.id
        }
        selectedTemplateId = new.id
        onSave()
    }

    private func addFromScan() {
        StatusBarController.shared.setPopoverBehavior(.applicationDefined)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "onboarding.template.panel_message")
        panel.level = .modalPanel

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let tree = FolderTemplateService.shared.scanFolderTree(at: url)
                var mapping = FolderTypeMapping()
                do {
                    mapping = try await FolderTemplateService.shared.analyzeStructure(
                        tree: tree,
                        deviceId: appState.config.anonymousId
                    )
                } catch {
                    #if DEBUG
                    print("Template scan: AI-analyse mislukt: \(error.localizedDescription)")
                    #endif
                }

                await MainActor.run {
                    let new = FolderStructureTemplate(
                        name: url.lastPathComponent,
                        folderTree: tree,
                        parameters: [],
                        mapping: mapping,
                        sourcePath: url.path
                    )
                    appState.config.folderTemplates.append(new)
                    if appState.config.defaultTemplateId == nil {
                        appState.config.defaultTemplateId = new.id
                    }
                    selectedTemplateId = new.id
                    onSave()
                }
            }
        }

        StatusBarController.shared.setPopoverBehavior(.transient)
    }

    private func duplicateSelected() {
        guard let template = selectedTemplate else { return }
        duplicate(template)
    }

    private func duplicate(_ template: FolderStructureTemplate) {
        var copy = template
        copy = FolderStructureTemplate(
            id: UUID(),
            name: template.name + " " + String(localized: "folder_structure.copy_suffix"),
            folderTree: deepCopy(template.folderTree),
            parameters: template.parameters.map {
                TemplateParameter(id: UUID(),
                                  title: $0.title,
                                  type: $0.type,
                                  defaultValue: $0.defaultValue,
                                  folderBreak: $0.folderBreak,
                                  cannotBeEmpty: $0.cannotBeEmpty)
            },
            mapping: template.mapping,
            sourcePath: template.sourcePath,
            createdAt: Date(),
            lastUpdatedAt: Date()
        )
        _ = copy
        appState.config.folderTemplates.append(copy)
        selectedTemplateId = copy.id
        onSave()
    }

    private func delete(_ template: FolderStructureTemplate) {
        appState.config.folderTemplates.removeAll(where: { $0.id == template.id })
        if appState.config.defaultTemplateId == template.id {
            appState.config.defaultTemplateId = appState.config.folderTemplates.first?.id
        }
        if selectedTemplateId == template.id {
            selectedTemplateId = appState.config.folderTemplates.first?.id
        }
        onSave()
    }

    private func setDefault(_ id: UUID) {
        appState.config.defaultTemplateId = id
        onSave()
    }

    private func startRename(_ template: FolderStructureTemplate) {
        let alert = NSAlert()
        alert.messageText = String(localized: "folder_structure.rename")
        alert.informativeText = String(localized: "folder_structure.rename_prompt")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "common.save"))
        alert.addButton(withTitle: String(localized: "common.cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.stringValue = template.name
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty, let idx = appState.config.folderTemplates.firstIndex(where: { $0.id == template.id }) {
                appState.config.folderTemplates[idx].name = newName
                appState.config.folderTemplates[idx].lastUpdatedAt = Date()
                onSave()
            }
        }
    }

    private func update(template: FolderStructureTemplate) {
        guard let idx = appState.config.folderTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        var updated = template
        updated.lastUpdatedAt = Date()
        appState.config.folderTemplates[idx] = updated
        onSave()
    }

    private func deepCopy(_ node: FolderNode) -> FolderNode {
        return FolderNode(
            id: UUID(),
            name: node.name,
            relativePath: node.relativePath,
            children: node.children.map { deepCopy($0) }
        )
    }
}

// MARK: - Sidebar row

private struct TemplateSidebarRow: View {
    let template: FolderStructureTemplate
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    let onSetDefault: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: isDefault ? "star.fill" : "folder")
                    .foregroundColor(isDefault ? .yellow : .secondary)
                    .font(.system(size: 11))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(template.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    if isDefault {
                        Text(String(localized: "folder_structure.default_badge"))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "folder_structure.set_default")) { onSetDefault() }
                .disabled(isDefault)
            Button(String(localized: "folder_structure.rename")) { onRename() }
            Button(String(localized: "folder_structure.duplicate")) { onDuplicate() }
            Divider()
            Button(String(localized: "folder_structure.delete"), role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Editor pane (detail)

private struct TemplateEditorPane: View {
    let template: FolderStructureTemplate
    let onUpdate: (FolderStructureTemplate) -> Void
    let onRename: () -> Void

    @State private var workingTemplate: FolderStructureTemplate
    @State private var isAnalyzing: Bool = false
    @State private var analyzeError: String?
    @State private var analyzeTask: Task<Void, Never>?

    init(template: FolderStructureTemplate,
         onUpdate: @escaping (FolderStructureTemplate) -> Void,
         onRename: @escaping () -> Void) {
        self.template = template
        self.onUpdate = onUpdate
        self.onRename = onRename
        _workingTemplate = State(initialValue: template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TemplateTreeEditor(
                        tree: $workingTemplate.folderTree,
                        parameters: workingTemplate.parameters,
                        onChange: { saveAndScheduleAnalysis() }
                    )

                    Divider()

                    TemplateParametersEditor(
                        parameters: $workingTemplate.parameters,
                        onChange: { pushUpdate() }
                    )

                    Divider()

                    mappingPreview

                    Divider()

                    treePreview
                }
                .padding(16)
            }
        }
        .onDisappear {
            analyzeTask?.cancel()
        }
    }

    // MARK: - Sub views

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
            Text(workingTemplate.name)
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            if let source = workingTemplate.sourcePath {
                Label {
                    Text(URL(fileURLWithPath: source).lastPathComponent)
                        .font(.system(size: 10))
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Button(action: onRename) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "folder_structure.rename"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mappingPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "folder_structure.editor.mapping"))
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                if isAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "folder_structure.editor.mapping_analyzing"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Button(String(localized: "settings.template.reanalyze")) {
                    triggerAnalysis()
                }
                .controlSize(.small)
                .disabled(isAnalyzing || workingTemplate.folderTree.children.isEmpty)
            }

            // Status-note: precies één melding tegelijk — prioriteit:
            // 1) Lege tree  2) Error (geen matches / netwerkfout)  3) Nooit geanalyseerd  4) Laatst geanalyseerd op X
            if workingTemplate.folderTree.children.isEmpty {
                Text(String(localized: "folder_structure.editor.mapping_no_tree"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            } else if let error = analyzeError {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .textSelection(.enabled)
                }
            } else if workingTemplate.mapping.analyzedAt == nil {
                Text(String(localized: "folder_structure.editor.mapping_empty_note"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else if let analyzedAt = workingTemplate.mapping.analyzedAt, hasAnyMapping {
                Text(String(format: String(localized: "folder_structure.editor.mapping_analyzed_at"), Self.timeFormatter.string(from: analyzedAt)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if !workingTemplate.folderTree.children.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    mappingRow("Music", path: workingTemplate.mapping.musicPath)
                    mappingRow("SFX", path: workingTemplate.mapping.sfxPath)
                    mappingRow("Voice Over", path: workingTemplate.mapping.voPath)
                    mappingRow("Graphics", path: workingTemplate.mapping.graphicsPath)
                    mappingRow("Motion Graphics", path: workingTemplate.mapping.motionGraphicsPath)
                    mappingRow("Stock Footage", path: workingTemplate.mapping.stockFootagePath)
                    mappingRow("Raw Footage", path: workingTemplate.mapping.rawFootagePath)
                    mappingRow("Photos", path: workingTemplate.mapping.photoPath)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private var hasAnyMapping: Bool {
        let m = workingTemplate.mapping
        return m.musicPath != nil || m.sfxPath != nil || m.voPath != nil ||
               m.graphicsPath != nil || m.motionGraphicsPath != nil ||
               m.stockFootagePath != nil || m.rawFootagePath != nil || m.photoPath != nil
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var treePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "folder_structure.editor.preview"))
                .font(.system(size: 12, weight: .semibold))

            let resolved = TemplatePlaceholderResolver.resolve(
                tree: workingTemplate.folderTree,
                parameters: workingTemplate.parameters,
                values: [:]
            )

            VStack(alignment: .leading, spacing: 2) {
                if resolved.children.isEmpty {
                    Text(String(localized: "folder_structure.editor.empty_preview"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(flatten(resolved, depth: 0), id: \.id) { row in
                        HStack(spacing: 4) {
                            Text(String(repeating: "  ", count: row.depth))
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            Text(row.name)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
    }

    private func mappingRow(_ label: String, path: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 100, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(path ?? "-")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(path != nil ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Logic

    private func pushUpdate() {
        onUpdate(workingTemplate)
    }

    private func saveAndScheduleAnalysis() {
        pushUpdate()
        analyzeTask?.cancel()
        analyzeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                triggerAnalysis()
            }
        }
    }

    private func triggerAnalysis() {
        guard !workingTemplate.folderTree.children.isEmpty else { return }
        isAnalyzing = true
        analyzeError = nil

        // Analyseer op de resolved tree met DEFAULT parameter-waarden (niet leeg),
        // zo blijven geen rauwe [Token]-placeholders in de folder-namen staan die
        // de AI zouden verwarren.
        var defaults: [String: String] = [:]
        for param in workingTemplate.parameters {
            let v = param.defaultValue.trimmingCharacters(in: .whitespaces)
            defaults[param.title] = v.isEmpty ? "Placeholder" : v
        }
        let resolved = TemplatePlaceholderResolver.resolve(
            tree: workingTemplate.folderTree,
            parameters: workingTemplate.parameters,
            values: defaults
        )

        #if DEBUG
        print("FolderStructureTemplate: Re-analyze gestart voor \(workingTemplate.name)")
        print("Tree: \(FolderTemplateService.shared.treeToString(resolved))")
        #endif

        Task { @MainActor in
            do {
                let mapping = try await FolderTemplateService.shared.analyzeStructure(
                    tree: resolved,
                    deviceId: AppState.shared.config.anonymousId
                )
                #if DEBUG
                print("FolderStructureTemplate: Mapping ontvangen — music=\(mapping.musicPath ?? "nil"), raw=\(mapping.rawFootagePath ?? "nil")")
                #endif
                // Check of alles nil is — dan AI kon niks matchen
                let isEmpty = mapping.musicPath == nil && mapping.sfxPath == nil &&
                              mapping.voPath == nil && mapping.graphicsPath == nil &&
                              mapping.motionGraphicsPath == nil && mapping.stockFootagePath == nil &&
                              mapping.rawFootagePath == nil && mapping.photoPath == nil

                // Merge: bewaar bestaande waarden niet — overschrijf met nieuwe (kan nil zijn).
                // Maar zet wel `analyzedAt` zodat we weten dat er geanalyseerd is.
                var newMapping = mapping
                newMapping.analyzedAt = Date()
                workingTemplate.mapping = newMapping
                isAnalyzing = false

                if isEmpty {
                    analyzeError = String(localized: "folder_structure.editor.mapping_no_match")
                }

                pushUpdate()
            } catch {
                #if DEBUG
                print("FolderStructureTemplate: Analyze error: \(error)")
                #endif
                analyzeError = error.localizedDescription
                isAnalyzing = false
            }
        }
    }

    // Flatten tree voor preview
    private struct FlatRow: Identifiable {
        let id = UUID()
        let name: String
        let depth: Int
    }

    private func flatten(_ node: FolderNode, depth: Int) -> [FlatRow] {
        var result: [FlatRow] = []
        for child in node.children {
            result.append(FlatRow(name: child.name, depth: depth))
            result.append(contentsOf: flatten(child, depth: depth + 1))
        }
        return result
    }
}

// MARK: - Tree editor

private struct TemplateTreeEditor: View {
    @Binding var tree: FolderNode
    let parameters: [TemplateParameter]
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "folder_structure.editor.tree"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: addRootChild) {
                    Label(String(localized: "folder_structure.tree.add_root"), systemImage: "plus")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                if tree.children.isEmpty {
                    Text(String(localized: "folder_structure.tree.empty"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(tree.children.enumerated()), id: \.element.id) { index, child in
                        TemplateTreeNodeRow(
                            node: Binding(
                                get: { tree.children[index] },
                                set: { tree.children[index] = $0 }
                            ),
                            depth: 0,
                            parameters: parameters,
                            onDelete: { deleteChild(at: index) },
                            onChange: onChange
                        )
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
    }

    private func addRootChild() {
        tree.children.append(FolderNode(name: String(localized: "folder_structure.tree.new_folder"), relativePath: "", children: []))
        onChange()
    }

    private func deleteChild(at index: Int) {
        tree.children.remove(at: index)
        onChange()
    }
}

// MARK: - Tree node row (recursive)

private struct TemplateTreeNodeRow: View {
    @Binding var node: FolderNode
    let depth: Int
    let parameters: [TemplateParameter]
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Indentatie
                Text(String(repeating: "  ", count: depth))

                // Disclosure
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14)
                .opacity(node.children.isEmpty ? 0.3 : 1.0)

                Image(systemName: "folder")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 11))

                TextField(String(localized: "folder_structure.tree.name_placeholder"),
                          text: Binding(
                            get: { node.name },
                            set: {
                                node = FolderNode(id: node.id, name: $0, relativePath: node.relativePath, children: node.children)
                                onChange()
                            }
                          ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))

                Spacer()

                Menu {
                    Button(String(localized: "folder_structure.tree.add_subfolder")) { addChild() }

                    Menu(String(localized: "folder_structure.insert_placeholder")) {
                        ForEach(parameters) { param in
                            Button("[\(param.title)]") { insertPlaceholder("[\(param.title)]") }
                        }
                        if !parameters.isEmpty { Divider() }
                        Button("[Date]") { insertPlaceholder("[Date]") }
                        Button("[Year]") { insertPlaceholder("[Year]") }
                        Button("[Month]") { insertPlaceholder("[Month]") }
                        Button("[Day]") { insertPlaceholder("[Day]") }
                    }

                    Divider()
                    Button(String(localized: "folder_structure.delete"), role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
            }

            if isExpanded {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, _ in
                    TemplateTreeNodeRow(
                        node: Binding(
                            get: { node.children[index] },
                            set: { node.children[index] = $0 }
                        ),
                        depth: depth + 1,
                        parameters: parameters,
                        onDelete: { deleteChild(at: index) },
                        onChange: onChange
                    )
                }
            }
        }
    }

    private func addChild() {
        var newChildren = node.children
        newChildren.append(FolderNode(name: String(localized: "folder_structure.tree.new_folder"), relativePath: "", children: []))
        node = FolderNode(id: node.id, name: node.name, relativePath: node.relativePath, children: newChildren)
        isExpanded = true
        onChange()
    }

    private func deleteChild(at index: Int) {
        var newChildren = node.children
        newChildren.remove(at: index)
        node = FolderNode(id: node.id, name: node.name, relativePath: node.relativePath, children: newChildren)
        onChange()
    }

    private func insertPlaceholder(_ token: String) {
        let newName = node.name.isEmpty ? token : "\(node.name)\(token)"
        node = FolderNode(id: node.id, name: newName, relativePath: node.relativePath, children: node.children)
        onChange()
    }
}

// MARK: - Parameters editor

private struct TemplateParametersEditor: View {
    @Binding var parameters: [TemplateParameter]
    let onChange: () -> Void

    @State private var showHelp: Bool = false

    // Compacte column widths (totaal ~360pt incl. trash + spacing, zodat hij
    // in de ~380pt brede detail-pane past zonder horizontale scroll).
    private let colType: CGFloat = 60
    private let colBreak: CGFloat = 34
    private let colRequired: CGFloat = 34
    private let colTrash: CGFloat = 22
    private let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(String(localized: "folder_structure.editor.parameters"))
                    .font(.system(size: 12, weight: .semibold))

                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "folder_structure.param.help_short"))
                .popover(isPresented: $showHelp, arrowEdge: .top) {
                    helpPopover
                }

                Spacer()

                Button(action: add) {
                    Label(String(localized: "folder_structure.param.add"), systemImage: "plus")
                        .font(.system(size: 11))
                        .labelStyle(.iconOnly)
                }
                .controlSize(.small)
                .help(String(localized: "folder_structure.param.add"))
            }

            if parameters.isEmpty {
                Text(String(localized: "folder_structure.param.empty"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Header — gebruik dezelfde rowLayout helper zodat kolommen
                    // exact onder elkaar uitlijnen met de rijen.
                    HStack(spacing: rowSpacing) {
                        Text(String(localized: "folder_structure.param.title"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(localized: "folder_structure.param.type"))
                            .frame(width: colType, alignment: .leading)
                        Text(String(localized: "folder_structure.param.default"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(localized: "folder_structure.param.folder_break_short"))
                            .frame(width: colBreak, alignment: .center)
                            .help(String(localized: "folder_structure.param.folder_break"))
                        Text(String(localized: "folder_structure.param.required_short"))
                            .frame(width: colRequired, alignment: .center)
                            .help(String(localized: "folder_structure.param.required"))
                        Spacer().frame(width: colTrash)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                    VStack(spacing: 4) {
                        ForEach(Array(parameters.enumerated()), id: \.element.id) { index, _ in
                            paramRow(index: index)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var helpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "folder_structure.param.help_title"))
                .font(.system(size: 13, weight: .semibold))

            Text(String(localized: "folder_structure.param.help_body"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                helpRow("folder_structure.param.title", "folder_structure.param.help_title_desc")
                helpRow("folder_structure.param.type", "folder_structure.param.help_type_desc")
                helpRow("folder_structure.param.default", "folder_structure.param.help_default_desc")
                helpRow("folder_structure.param.folder_break", "folder_structure.param.help_break_desc")
                helpRow("folder_structure.param.required", "folder_structure.param.help_required_desc")
            }

            Divider()

            Text(String(localized: "folder_structure.param.help_builtins"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(14)
        .frame(width: 340)
    }

    private func helpRow(_ labelKey: String.LocalizationValue, _ descKey: String.LocalizationValue) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(String(localized: labelKey))
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 86, alignment: .leading)
            Text(String(localized: descKey))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func paramRow(index: Int) -> some View {
        let paramId = parameters[index].id
        return HStack(spacing: rowSpacing) {
            TextField("", text: Binding(
                get: { parameters[index].title },
                set: { parameters[index].title = $0; onChange() }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(maxWidth: .infinity)

            Picker("", selection: Binding(
                get: { parameters[index].type },
                set: { parameters[index].type = $0; onChange() }
            )) {
                Text("Text").tag(TemplateParamType.text)
                Text("Number").tag(TemplateParamType.number)
            }
            .labelsHidden()
            .frame(width: colType)

            TextField("", text: Binding(
                get: { parameters[index].defaultValue },
                set: { parameters[index].defaultValue = $0; onChange() }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(maxWidth: .infinity)

            Toggle("", isOn: Binding(
                get: { parameters[index].folderBreak },
                set: { parameters[index].folderBreak = $0; onChange() }
            ))
            .labelsHidden()
            .frame(width: colBreak, alignment: .center)

            Toggle("", isOn: Binding(
                get: { parameters[index].cannotBeEmpty },
                set: { parameters[index].cannotBeEmpty = $0; onChange() }
            ))
            .labelsHidden()
            .frame(width: colRequired, alignment: .center)

            // Trash: id-based delete zodat hij ook werkt na reorder / add,
            // grotere hit-area en .borderless voor duidelijke macOS-feel.
            Button(action: { removeById(paramId) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .frame(width: colTrash, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "folder_structure.delete"))
        }
    }

    private func add() {
        parameters.append(TemplateParameter(
            title: String(localized: "folder_structure.param.new_name"),
            type: .text,
            defaultValue: "",
            folderBreak: false,
            cannotBeEmpty: false
        ))
        onChange()
    }

    /// ID-based remove — robuust tegen state-mismatches tussen rendering en click-tijd.
    private func removeById(_ id: UUID) {
        guard let idx = parameters.firstIndex(where: { $0.id == id }) else { return }
        parameters.remove(at: idx)
        onChange()
    }
}
