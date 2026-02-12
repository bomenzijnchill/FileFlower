import SwiftUI
import AppKit

/// View voor het beheren van folder syncs
struct FolderSyncView: View {
    @StateObject private var appState = AppState.shared
    @State private var showingAddForm = false
    @State private var selectedSyncForEdit: FolderSync?
    @Binding var isShowingForm: Bool
    
    init(isShowingForm: Binding<Bool> = .constant(false)) {
        self._isShowingForm = isShowingForm
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Als we een form tonen, toon die in plaats van de lijst
            if showingAddForm {
                AddFolderSyncForm(onDismiss: { 
                    showingAddForm = false
                    isShowingForm = false
                })
            } else if let sync = selectedSyncForEdit {
                EditFolderSyncForm(sync: sync, onDismiss: { 
                    selectedSyncForEdit = nil
                    isShowingForm = false
                })
            } else {
                // Normale lijst view
                folderSyncListContent
            }
        }
        .onChange(of: showingAddForm) { _, newValue in
            isShowingForm = newValue || selectedSyncForEdit != nil
        }
        .onChange(of: selectedSyncForEdit) { _, newValue in
            isShowingForm = showingAddForm || newValue != nil
        }
    }
    
    /// Groepeer syncs per project
    private var syncsByProject: [(projectPath: String, projectName: String, syncs: [FolderSync])] {
        let grouped = Dictionary(grouping: appState.config.folderSyncs) { $0.projectPath }
        return grouped.map { (projectPath, syncs) in
            let projectName = URL(fileURLWithPath: projectPath).deletingPathExtension().lastPathComponent
            return (projectPath: projectPath, projectName: projectName, syncs: syncs)
        }.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
    }
    
    private var folderSyncListContent: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: { showingAddForm = true }) {
                    Label(String(localized: "foldersync.add_folder"), systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
                
                if !appState.config.folderSyncs.isEmpty {
                    Text(String(localized: "foldersync.folder_count \(appState.config.folderSyncs.count)"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            // Content
            if appState.config.folderSyncs.isEmpty {
                EmptyFolderSyncView(onAdd: { showingAddForm = true })
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(syncsByProject, id: \.projectPath) { group in
                            // Project header
                            ProjectGroupHeader(
                                projectName: group.projectName,
                                syncCount: group.syncs.count,
                                isExpanded: expandedProjects.contains(group.projectPath),
                                onToggle: { toggleProjectExpansion(group.projectPath) },
                                onDeleteAll: { deleteAllSyncsForProject(group.projectPath) }
                            )
                            
                            // Syncs voor dit project (als expanded)
                            if expandedProjects.contains(group.projectPath) {
                                ForEach(group.syncs) { sync in
                                    FolderSyncRow(
                                        sync: sync,
                                        status: appState.folderSyncStatuses[sync.id] ?? .idle,
                                        onToggle: { appState.toggleFolderSync(syncId: sync.id) },
                                        onEdit: { selectedSyncForEdit = sync },
                                        onDelete: { appState.removeFolderSync(syncId: sync.id) },
                                        onForceSync: { appState.forceFolderSync(syncId: sync.id) },
                                        onOpenInFinder: { openInFinder(path: sync.folderPath) },
                                        isCompact: true
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .padding(.leading, 8) // Extra indent
                                    
                                    if sync.id != group.syncs.last?.id {
                                        Divider()
                                            .padding(.horizontal, 20)
                                    }
                                }
                            }
                            
                            if group.projectPath != syncsByProject.last?.projectPath {
                                Divider()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Standaard alle projecten uitklappen
            expandedProjects = Set(syncsByProject.map { $0.projectPath })
        }
    }
    
    @State private var expandedProjects: Set<String> = []
    
    private func toggleProjectExpansion(_ projectPath: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedProjects.contains(projectPath) {
                expandedProjects.remove(projectPath)
            } else {
                expandedProjects.insert(projectPath)
            }
        }
    }
    
    private func deleteAllSyncsForProject(_ projectPath: String) {
        // Vind alle syncs voor dit project en verwijder ze
        let syncsToDelete = appState.config.folderSyncs.filter { $0.projectPath == projectPath }
        for sync in syncsToDelete {
            appState.removeFolderSync(syncId: sync.id)
        }
    }
    
    private func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}

/// Lege state view
struct EmptyFolderSyncView: View {
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(String(localized: "foldersync.no_folders"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(String(localized: "foldersync.add_folder_description"))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Button(action: onAdd) {
                Label(String(localized: "foldersync.add_folder"), systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Header voor een project groep
struct ProjectGroupHeader: View {
    let projectName: String
    let syncCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDeleteAll: () -> Void
    
    @State private var isHovered = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Expand/collapse button
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        
                        Image(systemName: "film")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        
                        Text(projectName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(String(localized: "foldersync.folder_count \(syncCount)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Delete all button (alleen zichtbaar bij hover)
                if isHovered {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = true
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(String(localized: "foldersync.delete_all_for_project"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            
            // Delete confirmatie
            if showDeleteConfirmation {
                ProjectDeleteConfirmation(
                    projectName: projectName,
                    syncCount: syncCount,
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDeleteAll()
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }
}

/// Delete confirmatie voor een heel project
struct ProjectDeleteConfirmation: View {
    let projectName: String
    let syncCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "foldersync.delete_all_title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(String(localized: "foldersync.delete_all_message \(syncCount) \(projectName)"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            HStack(spacing: 10) {
                Spacer()
                
                Button(String(localized: "common.cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "foldersync.delete_all_button")) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/// Row voor een enkele folder sync
struct FolderSyncRow: View {
    let sync: FolderSync
    let status: FolderSyncStatus
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onForceSync: () -> Void
    let onOpenInFinder: () -> Void
    var isCompact: Bool = false
    
    @State private var isHovered = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: isCompact ? 8 : 12) {
            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { sync.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            
            // Folder icon
            Image(systemName: sync.folderExists ? "folder.fill" : "folder.fill.badge.questionmark")
                .font(.system(size: isCompact ? 16 : 20))
                .foregroundColor(sync.folderExists ? .accentColor.opacity(0.7) : .red.opacity(0.7))
                .frame(width: isCompact ? 24 : 32)
            
            // Content
            VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
                Text(sync.folderName)
                    .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(sync.isEnabled ? .primary : .secondary)
                
                if isCompact {
                    // Compacte weergave: alleen bin path + status
                    HStack(spacing: 6) {
                        if !sync.premiereBinRoot.isEmpty {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(sync.premiereBinRoot)
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                                .lineLimit(1)
                        } else {
                            Text("→ \(sync.folderName)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Compacte status indicator
                        FolderSyncStatusIndicator(status: status)
                    }
                } else {
                    HStack(spacing: 6) {
                        // Project naam
                        Image(systemName: "film")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(sync.projectName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        // Bin root (als ingesteld)
                        if !sync.premiereBinRoot.isEmpty {
                            Text("→")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(sync.premiereBinRoot)
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                                .lineLimit(1)
                        }
                    }
                    
                    // Status
                    FolderSyncStatusBadge(status: status, lastSyncDate: sync.lastSyncDate)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 6) {
                // Open in Finder
                Button(action: onOpenInFinder) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open in Finder")
                
                // Force sync
                Button(action: onForceSync) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!sync.isEnabled)
                .help(String(localized: "foldersync.force_sync"))
                
                // Edit
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "common.edit"))
                
                // Delete
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = true 
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "common.delete"))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        
        // Uitschuifbare delete confirmatie ONDER de row
        if showDeleteConfirmation {
            InlineDeleteConfirmation(
                folderName: sync.folderName,
                onConfirm: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = false
                    }
                    // Kleine delay voor smooth animatie
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDelete()
                    }
                },
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = false
                    }
                }
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
        }
        } // einde VStack
    }
}

/// Inline uitschuifbare delete confirmatie - volle breedte onder de row
struct InlineDeleteConfirmation: View {
    let folderName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "foldersync.delete_folder_title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(String(localized: "foldersync.delete_folder_message \(folderName)"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            HStack(spacing: 10) {
                Spacer()
                
                Button(String(localized: "common.cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "common.delete")) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                )
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// Compacte status indicator (alleen icoon)
struct FolderSyncStatusIndicator: View {
    let status: FolderSyncStatus
    
    var body: some View {
        switch status {
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green.opacity(0.7))
        case .syncing:
            ProgressView()
                .scaleEffect(0.5)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
        }
    }
}

/// Status badge voor folder sync
struct FolderSyncStatusBadge: View {
    let status: FolderSyncStatus
    let lastSyncDate: Date?
    
    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .idle:
                if let date = lastSyncDate {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text(String(localized: "foldersync.last_sync \(formatDate(date))"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(String(localized: "foldersync.waiting"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
            case .syncing(let progress, let file):
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(Int(progress * 100))% - \(file)")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                
            case .completed(let count):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text(String(localized: "foldersync.files_synced \(count)"))
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Inline form voor het toevoegen van een nieuwe folder sync
struct AddFolderSyncForm: View {
    let onDismiss: () -> Void
    @StateObject private var appState = AppState.shared
    
    @State private var selectedFolderPath: String = ""
    @State private var selectedProjectPath: String = ""
    @State private var premiereBinRoot: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Text(String(localized: "foldersync.new_sync"))
                    .font(.headline)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 36)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Folder selectie
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "foldersync.source_folder"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack {
                            if selectedFolderPath.isEmpty {
                                Text(String(localized: "foldersync.select_folder"))
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: selectedFolderPath).lastPathComponent)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Text(selectedFolderPath)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Button(String(localized: "foldersync.choose_folder")) {
                                selectFolder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    
                    // Project selectie
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "foldersync.premiere_project"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedProjectPath) {
                            Text(String(localized: "foldersync.select_project")).tag("")
                            ForEach(appState.recentProjects) { project in
                                Text(project.name).tag(project.projectPath)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    // Premiere bin root (optioneel)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "foldersync.premiere_bin"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField(String(localized: "foldersync.bin_placeholder"), text: $premiereBinRoot)
                            .textFieldStyle(.roundedBorder)

                        Text(String(localized: "foldersync.bin_description"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button(String(localized: "common.cancel")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(String(localized: "common.add")) {
                    addSync()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedFolderPath.isEmpty || selectedProjectPath.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
    }
    
    private func selectFolder() {
        // Gebruik DispatchQueue om de panel te openen nadat de huidige event loop is afgerond
        // Dit voorkomt problemen met MenuBarExtra
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = String(localized: "foldersync.select_folder_panel")
            panel.level = .modalPanel // Zorg dat de panel bovenop komt
            
            if panel.runModal() == .OK, let url = panel.url {
                self.selectedFolderPath = url.path
            }
        }
    }
    
    private func addSync() {
        appState.addFolderSync(
            folderPath: selectedFolderPath,
            projectPath: selectedProjectPath,
            premiereBinRoot: premiereBinRoot
        )
        onDismiss()
    }
}

/// Inline form voor het bewerken van een folder sync
struct EditFolderSyncForm: View {
    let sync: FolderSync
    let onDismiss: () -> Void
    @StateObject private var appState = AppState.shared
    
    @State private var premiereBinRoot: String = ""
    @State private var selectedProjectPath: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Text(String(localized: "foldersync.edit_sync"))
                    .font(.headline)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 36)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Folder info (niet bewerkbaar)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "foldersync.source_folder"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sync.folderName)
                                .font(.system(size: 13, weight: .medium))
                            Text(sync.folderPath)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    
                    // Project selectie
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "foldersync.premiere_project"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedProjectPath) {
                            ForEach(appState.recentProjects) { project in
                                Text(project.name).tag(project.projectPath)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    // Premiere bin root
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "foldersync.premiere_bin"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField(String(localized: "foldersync.bin_placeholder"), text: $premiereBinRoot)
                            .textFieldStyle(.roundedBorder)

                        Text(String(localized: "foldersync.bin_empty_description \(sync.folderName)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button(String(localized: "common.cancel")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(String(localized: "common.save")) {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .onAppear {
            premiereBinRoot = sync.premiereBinRoot
            selectedProjectPath = sync.projectPath
        }
    }
    
    private func saveChanges() {
        // Update bin root
        appState.updateFolderSyncBinRoot(syncId: sync.id, binRoot: premiereBinRoot)
        
        // Als project is gewijzigd, update dat ook
        if selectedProjectPath != sync.projectPath {
            if let index = appState.config.folderSyncs.firstIndex(where: { $0.id == sync.id }) {
                appState.config.folderSyncs[index].projectPath = selectedProjectPath
                appState.saveConfig()
                
                // Herstart de watcher met nieuwe config
                let updatedSync = appState.config.folderSyncs[index]
                FolderSyncWatcher.shared.restartSync(sync: updatedSync)
            }
        }
        
        onDismiss()
    }
}

#Preview {
    FolderSyncView(isShowingForm: .constant(false))
        .frame(width: 500, height: 400)
}




