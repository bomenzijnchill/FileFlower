import SwiftUI
import AppKit

/// Tab view voor het beheren en laden van veelgebruikte mappen in Premiere
struct LoadFolderView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var showingAddForm = false
    @State private var editingPreset: LoadFolderPreset?
    @State private var loadingPresetId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if showingAddForm {
                AddLoadFolderForm(
                    onSave: { folderPath, displayName, binPath in
                        appState.addLoadFolderPreset(
                            folderPath: folderPath,
                            displayName: displayName,
                            premiereBinPath: binPath
                        )
                        showingAddForm = false
                    },
                    onCancel: { showingAddForm = false }
                )
                .transition(.move(edge: .trailing))
            } else if let preset = editingPreset {
                EditLoadFolderForm(
                    preset: preset,
                    onSave: { displayName, binPath in
                        appState.updateLoadFolderPreset(
                            presetId: preset.id,
                            displayName: displayName,
                            premiereBinPath: binPath
                        )
                        editingPreset = nil
                    },
                    onCancel: { editingPreset = nil }
                )
                .transition(.move(edge: .trailing))
            } else if appState.config.loadFolderPresets.isEmpty {
                EmptyLoadFolderView(onAdd: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingAddForm = true
                    }
                })
            } else {
                // Toolbar
                HStack(spacing: 8) {
                    Text(String(localized: "loadfolder.title"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingAddForm = true
                        }
                    }) {
                        Label(String(localized: "loadfolder.add"), systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

                // Preset lijst
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.config.loadFolderPresets) { preset in
                            LoadFolderPresetRow(
                                preset: preset,
                                isLoading: loadingPresetId == preset.id,
                                onLoad: { loadPreset(preset) },
                                onEdit: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        editingPreset = preset
                                    }
                                },
                                onDelete: {
                                    appState.removeLoadFolderPreset(presetId: preset.id)
                                }
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func loadPreset(_ preset: LoadFolderPreset) {
        loadingPresetId = preset.id
        Task {
            await appState.loadFolderIntoProject(preset: preset)
            await MainActor.run {
                loadingPresetId = nil
            }
        }
    }
}

/// Rij voor een LoadFolder preset
struct LoadFolderPresetRow: View {
    let preset: LoadFolderPreset
    let isLoading: Bool
    let onLoad: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Folder icon
            Image(systemName: preset.folderExists ? "folder.fill" : "folder.badge.questionmark")
                .font(.system(size: 20))
                .foregroundColor(preset.folderExists ? .accentColor.opacity(0.7) : .red.opacity(0.6))
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(preset.folderName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let binPath = preset.premiereBinPath, !binPath.isEmpty {
                        Text("→")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(binPath)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                }

                if !preset.folderExists {
                    Text(String(localized: "loadfolder.folder_not_found"))
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                // Context menu voor edit/delete
                Menu {
                    Button(action: onEdit) {
                        Label(String(localized: "loadfolder.edit"), systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label(String(localized: "loadfolder.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Laden button
                Button(action: onLoad) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Label(String(localized: "loadfolder.load"), systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!preset.folderExists || isLoading)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Formulier om een nieuwe LoadFolder preset toe te voegen
struct AddLoadFolderForm: View {
    let onSave: (String, String, String?) -> Void
    let onCancel: () -> Void

    @State private var folderPath = ""
    @State private var displayName = ""
    @State private var premiereBinPath = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onCancel()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Text(String(localized: "loadfolder.add_title"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Map selecteren
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "loadfolder.folder_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack {
                        Text(folderPath.isEmpty ? String(localized: "loadfolder.no_folder_selected") : URL(fileURLWithPath: folderPath).lastPathComponent)
                            .font(.system(size: 12))
                            .foregroundColor(folderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(String(localized: "loadfolder.choose_folder")) {
                            chooseFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }

                // Naam
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "loadfolder.name_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField(String(localized: "loadfolder.name_placeholder"), text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Optioneel bin pad
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "loadfolder.bin_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField(String(localized: "loadfolder.bin_placeholder"), text: $premiereBinPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Opslaan
                HStack {
                    Spacer()
                    Button(String(localized: "loadfolder.save")) {
                        onSave(folderPath, displayName, premiereBinPath.isEmpty ? nil : premiereBinPath)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(folderPath.isEmpty || displayName.isEmpty)
                }
            }
            .padding(12)

            Spacer()
        }
    }

    private func chooseFolder() {
        // Zet popover behavior tijdelijk zodat het niet sluit
        StatusBarController.shared.setPopoverBehavior(.applicationDefined)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "loadfolder.choose_folder_message")

        panel.begin { response in
            DispatchQueue.main.async {
                // Herstel popover behavior
                StatusBarController.shared.setPopoverBehavior(.transient)

                if response == .OK, let url = panel.url {
                    folderPath = url.path
                    if displayName.isEmpty {
                        displayName = url.lastPathComponent
                    }
                }
            }
        }
    }
}

/// Formulier om een bestaande LoadFolder preset te bewerken
struct EditLoadFolderForm: View {
    let preset: LoadFolderPreset
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var displayName: String
    @State private var premiereBinPath: String

    init(preset: LoadFolderPreset, onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.preset = preset
        self.onSave = onSave
        self.onCancel = onCancel
        self._displayName = State(initialValue: preset.displayName)
        self._premiereBinPath = State(initialValue: preset.premiereBinPath ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onCancel()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Text(String(localized: "loadfolder.edit_title"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Map (niet bewerkbaar)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "loadfolder.folder_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(preset.folderPath)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                // Naam
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "loadfolder.name_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField(String(localized: "loadfolder.name_placeholder"), text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Optioneel bin pad
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "loadfolder.bin_label"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField(String(localized: "loadfolder.bin_placeholder"), text: $premiereBinPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Opslaan
                HStack {
                    Spacer()
                    Button(String(localized: "loadfolder.save")) {
                        onSave(displayName, premiereBinPath.isEmpty ? nil : premiereBinPath)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(displayName.isEmpty)
                }
            }
            .padding(12)

            Spacer()
        }
    }
}

/// Empty state voor LoadFolder tab
struct EmptyLoadFolderView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text(String(localized: "loadfolder.empty_title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(String(localized: "loadfolder.empty_description"))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: onAdd) {
                Label(String(localized: "loadfolder.add_first"), systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
