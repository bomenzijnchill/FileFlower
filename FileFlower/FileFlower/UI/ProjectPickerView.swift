import SwiftUI

struct ProjectPickerView: View {
    let item: DownloadItem?
    var onDismiss: (() -> Void)?
    
    @StateObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProject: ProjectInfo?
    @State private var selectedType: AssetType = .music
    @State private var selectedSubfolder: String = ""
    @State private var selectedSfxCategory: String = ""
    @State private var showingSubfolderPicker = false
    
    // Veelgebruikte SFX categorieën (gebaseerd op Epidemic Sound)
    private let sfxCategories = [
        // Impacts & Hits
        "Impacts", "Hits", "Punches", "Crashes", "Explosions",
        // Transitions
        "Risers", "Swooshes", "Whooshes", "Swishes", "Downers",
        // Designed
        "Designed", "Cinematic", "Sci-Fi", "Horror",
        // Foley
        "Foley", "Footsteps", "Cloth", "Props",
        // Ambience
        "Ambience", "Nature", "Urban", "Room Tone",
        // UI & Tech
        "UI", "Clicks", "Beeps", "Notifications", "Glitches",
        // Miscellaneous
        "Cartoon", "Comedy", "Magic", "Weapons", "Vehicles"
    ]
    
    init(item: DownloadItem? = nil, onDismiss: (() -> Void)? = nil) {
        self.item = item
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.plus")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text(String(localized: "picker.choose_project_type"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Content
            VStack(spacing: 20) {
                // Project selection
                VStack(alignment: .leading, spacing: 10) {
                    Label("Project", systemImage: "folder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("Project", selection: $selectedProject) {
                        Text(String(localized: "picker.none_selected")).tag(ProjectInfo?.none)
                        ForEach(appState.recentProjects) { project in
                            Text(project.name).tag(ProjectInfo?.some(project))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedProject) { _, _ in
                        // Prevent dismissal on selection change
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Type selection
                VStack(alignment: .leading, spacing: 10) {
                    Label("Type", systemImage: "tag")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach(AssetType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                            Label(type.displayName, systemImage: iconForType(type))
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 20)
                
                // Subfolder selection (for Music)
                if selectedType == .music {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "picker.subfolder_mood_genre"), systemImage: "folder.badge.gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            Picker(String(localized: "picker.mood_genre"), selection: $selectedSubfolder) {
                                Text(String(localized: "common.none")).tag("")
                                ForEach(subfolderOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            
                            Button(action: {
                                showingSubfolderPicker = true
                            }) {
                                Label(String(localized: "common.new"), systemImage: "plus.circle")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // SFX Categorie selection (for SFX)
                if selectedType == .sfx {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "picker.sfx_category"), systemImage: "waveform.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Picker(String(localized: "picker.category"), selection: $selectedSfxCategory) {
                            Text(String(localized: "picker.no_category")).tag("")
                            ForEach(sfxCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Button(String(localized: "common.cancel")) {
                    if let windowController = ProjectPickerWindowController.shared {
                        windowController.close()
                    } else if let onDismiss = onDismiss {
                        // Gebruik onDismiss callback als we in QueuePopupView context zijn
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(String(localized: "common.confirm")) {
                    confirmSelection()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedProject == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingSubfolderPicker) {
            SubfolderInputView(subfolder: $selectedSubfolder)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if let item = item {
                selectedProject = item.targetProject ?? appState.preferredProject
                selectedType = item.predictedType
                selectedSubfolder = item.targetSubfolder ?? ""
                selectedSfxCategory = item.predictedSfxCategory ?? ""
            } else {
                selectedProject = appState.preferredProject
            }
        }
    }
    
    private func iconForType(_ type: AssetType) -> String {
        switch type {
        case .music: return "music.note"
        case .sfx: return "waveform"
        case .vo: return "mic"
        case .motionGraphic: return "video"
        case .graphic: return "photo"
        case .stockFootage: return "film"
        case .unknown: return "questionmark"
        }
    }
    
    private var subfolderOptions: [String] {
        if appState.config.musicClassification == .mood {
            return MoodList.shared.moods
        } else {
            return GenreList.shared.genres
        }
    }
    
    private func confirmSelection() {
        guard let project = selectedProject else { return }
        
        // Update the specific item if provided
        if let item = item {
            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                appState.queuedItems[index].targetProject = project
                appState.queuedItems[index].predictedType = selectedType
                appState.queuedItems[index].targetSubfolder = selectedSubfolder.isEmpty ? nil : selectedSubfolder
                // Sla SFX categorie op als type SFX is
                if selectedType == .sfx {
                    appState.queuedItems[index].predictedSfxCategory = selectedSfxCategory.isEmpty ? nil : selectedSfxCategory
                }
            }
        }
        
        // Close window/view - gebruik onDismiss als beschikbaar (QueuePopupView context)
        if let windowController = ProjectPickerWindowController.shared {
            windowController.close()
            onDismiss?()
        } else if let onDismiss = onDismiss {
            // We zijn in QueuePopupView context - gebruik alleen onDismiss
            onDismiss()
        } else {
            dismiss()
        }
    }
}

struct SubfolderInputView: View {
    @Binding var subfolder: String
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Label(String(localized: "picker.new_subfolder"), systemImage: "folder.badge.plus")
                .font(.system(size: 15, weight: .semibold))

            TextField(String(localized: "picker.name"), text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !input.isEmpty {
                        subfolder = input
                        dismiss()
                    }
                }
            
            HStack(spacing: 12) {
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("OK") {
                    subfolder = input
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

