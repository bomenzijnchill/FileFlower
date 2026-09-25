import SwiftUI
import AppKit

struct RowEditSheet: View {
    let itemId: UUID
    let onDismiss: () -> Void

    @ObservedObject private var appState = AppState.shared
    @State private var newSubfolderName = ""
    @State private var isAddingSubfolder = false
    @State private var cachedSubfolders: [String] = []
    @State private var didLoadSubfolders = false

    private let sfxCategories = [
        "Impacts", "Hits", "Punches", "Crashes", "Explosions",
        "Risers", "Swooshes", "Whooshes", "Swishes", "Downers",
        "Designed", "Cinematic", "Sci-Fi", "Horror",
        "Foley", "Footsteps", "Cloth", "Props",
        "Ambience", "Nature", "Urban", "Room Tone",
        "UI", "Clicks", "Beeps", "Notifications", "Glitches",
        "Cartoon", "Comedy", "Magic", "Weapons", "Vehicles"
    ]

    private var itemIndex: Int? {
        appState.queuedItems.firstIndex(where: { $0.id == itemId })
    }

    private var item: DownloadItem? {
        guard let idx = itemIndex else { return nil }
        return appState.queuedItems[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formContent
            Divider()
            footer
        }
        .frame(width: 360)
        .background(Color.popSurface)
        .task {
            await loadSubfoldersInBackground()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let item = item {
                ThumbnailView(
                    path: item.path,
                    isFolder: item.isFolder,
                    assetType: item.predictedType,
                    isClassifying: false
                )
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let preview = item.previewPath, !preview.isEmpty {
                        Text(preview)
                            .font(.brandMono(size: 11))
                            .foregroundColor(.ink3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let item = item, let idx = itemIndex {
                // Type
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "edit.type"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.ink3)
                    Picker("", selection: Binding(
                        get: { item.predictedType },
                        set: { newType in
                            let oldType = appState.queuedItems[idx].predictedType
                            guard oldType != newType else { return }
                            appState.queuedItems[idx].predictedType = newType
                            // Mood/genre/categorie horen bij het OUDE type — laten staan
                            // zou het bestand in een submap van het vorige type plaatsen
                            // (bv. footage in Music/Mood/Epic).
                            appState.queuedItems[idx].predictedMood = nil
                            appState.queuedItems[idx].predictedGenre = nil
                            appState.queuedItems[idx].predictedSfxCategory = nil
                            appState.queuedItems[idx].targetSubfolder = nil
                            CorrectionHistoryManager.shared.recordCorrection(
                                item: appState.queuedItems[idx],
                                originalType: oldType,
                                correctedType: newType
                            )
                            updatePreviewPath(at: idx)
                        }
                    )) {
                        ForEach(AssetType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                            Label(type.displayName, systemImage: iconForType(type)).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                // Mood (music only, mood mode)
                if item.predictedType == .music && appState.config.musicClassification == .mood {
                    moodPicker(at: idx)
                }

                // Genre (music only, genre mode)
                if item.predictedType == .music && appState.config.musicClassification == .genre {
                    genrePicker(at: idx)
                }

                // SFX category
                if item.predictedType == .sfx {
                    sfxCategoryPicker(at: idx)
                }

                // Subfolder
                subfolderPicker(item: item, at: idx)

                // Manual path override
                if let preview = item.previewPath, !preview.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "edit.target_path"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.ink3)
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.ink4)
                            Text(preview)
                                .font(.brandMono(size: 11))
                                .foregroundColor(item.manualTargetPath != nil ? .blue : .ink2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(action: { showPathEditor() }) {
                                Label(String(localized: "edit.change_path"), systemImage: "pencil")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(String(localized: "common.cancel")) {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.ink3)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(action: onDismiss) {
                Text(String(localized: "edit.save"))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.brandBurntPeach)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Pickers

    private func moodPicker(at idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "edit.mood"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.ink3)
            Picker("", selection: Binding(
                get: { appState.queuedItems[idx].predictedMood ?? "" },
                set: { newVal in
                    appState.queuedItems[idx].predictedMood = newVal.isEmpty ? nil : newVal
                    updatePreviewPath(at: idx)
                }
            )) {
                Text(String(localized: "edit.none")).tag("")
                Divider()
                ForEach(MoodList.shared.moods, id: \.self) { mood in
                    Text(mood).tag(mood)
                }
            }
            .labelsHidden()
        }
    }

    private func genrePicker(at idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "edit.genre"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.ink3)
            Picker("", selection: Binding(
                get: { appState.queuedItems[idx].predictedGenre ?? "" },
                set: { newVal in
                    appState.queuedItems[idx].predictedGenre = newVal.isEmpty ? nil : newVal
                    updatePreviewPath(at: idx)
                }
            )) {
                Text(String(localized: "edit.none")).tag("")
                Divider()
                ForEach(GenreList.shared.genres, id: \.self) { genre in
                    Text(genre).tag(genre)
                }
            }
            .labelsHidden()
        }
    }

    private func sfxCategoryPicker(at idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "edit.category"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.ink3)
            Picker("", selection: Binding(
                get: { appState.queuedItems[idx].predictedSfxCategory ?? "" },
                set: { newVal in
                    appState.queuedItems[idx].predictedSfxCategory = newVal.isEmpty ? nil : newVal
                    updatePreviewPath(at: idx)
                }
            )) {
                Text(String(localized: "edit.none")).tag("")
                Divider()
                ForEach(sfxCategories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .labelsHidden()
        }
    }

    private func subfolderPicker(item: DownloadItem, at idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "edit.subfolder"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.ink3)

            if isAddingSubfolder {
                HStack(spacing: 4) {
                    TextField(String(localized: "edit.subfolder_name"), text: $newSubfolderName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            let trimmed = newSubfolderName.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                appState.queuedItems[idx].targetSubfolder = trimmed
                                updatePreviewPath(at: idx)
                            }
                            isAddingSubfolder = false
                            newSubfolderName = ""
                        }
                    Button(action: { isAddingSubfolder = false; newSubfolderName = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.ink3)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    Menu {
                        Button(action: {
                            appState.queuedItems[idx].targetSubfolder = nil
                            updatePreviewPath(at: idx)
                        }) {
                            if item.targetSubfolder == nil {
                                Label(String(localized: "queue.no_subfolder"), systemImage: "checkmark")
                            } else {
                                Text(String(localized: "queue.no_subfolder"))
                            }
                        }

                        if !cachedSubfolders.isEmpty {
                            Divider()
                            ForEach(cachedSubfolders, id: \.self) { subfolder in
                                Button(action: {
                                    appState.queuedItems[idx].targetSubfolder = subfolder
                                    updatePreviewPath(at: idx)
                                }) {
                                    if subfolder == item.targetSubfolder {
                                        Label(subfolder, systemImage: "checkmark")
                                    } else {
                                        Text(subfolder)
                                    }
                                }
                            }
                        }

                        Divider()
                        Button(action: { isAddingSubfolder = true }) {
                            Label(String(localized: "edit.new_subfolder"), systemImage: "plus")
                        }
                    } label: {
                        Text(item.targetSubfolder ?? String(localized: "queue.no_subfolder"))
                            .font(.system(size: 12))
                            .foregroundColor(item.targetSubfolder != nil ? .destChipInk : .ink3)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    // MARK: - Helpers

    private func updatePreviewPath(at index: Int) {
        let item = appState.queuedItems[index]
        guard let project = item.targetProject, item.predictedType != .unknown else {
            appState.queuedItems[index].previewPath = nil
            return
        }
        let subfolder = item.targetSubfolder ?? item.predictedMood ?? item.predictedGenre
        appState.queuedItems[index].previewPath = PathResolver.shared.previewRelativePath(
            project: project,
            assetType: item.predictedType,
            subfolder: subfolder,
            musicMode: appState.config.musicClassification,
            sfxCategory: item.predictedSfxCategory
        )
    }

    private func loadSubfoldersInBackground() async {
        guard !didLoadSubfolders, let item = item else { return }
        didLoadSubfolders = true

        let predictedType = item.predictedType
        // Hoofd-projectmap vooraf op de main thread bepalen (de echte asset-map, NIET de .prproj-map);
        // alleen het pad (waarde-type) capturen in de detached task.
        let mainFolderPath = item.targetProject.map { PathResolver.shared.projectMainFolderURL(for: $0).path }

        let result: [String] = await Task.detached(priority: .userInitiated) {
            guard let mainFolderPath = mainFolderPath,
                  predictedType != .unknown,
                  predictedType != .sfx,
                  predictedType != .music else { return [] }

            let rootURL = URL(fileURLWithPath: mainFolderPath)
            guard let folderName = await MainActor.run(body: {
                BinMatcher.shared.findMatchingFolder(for: predictedType, in: rootURL)
            }) else { return [] }

            let targetFolderURL = rootURL.appendingPathComponent(folderName)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: targetFolderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return contents
                .filter { url in
                    var isDir: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                }
                .map { $0.lastPathComponent }
                .sorted()
        }.value

        await MainActor.run {
            cachedSubfolders = result
        }
    }

    private func showPathEditor() {
        guard let item = item else { return }
        // Voorkom dat de transient popover sluit terwijl de folder picker open is
        StatusBarController.shared.setPopoverBehavior(.applicationDefined)
        defer { StatusBarController.shared.setPopoverBehavior(.transient) }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "edit.choose_target_message")
        panel.prompt = String(localized: "edit.choose")
        panel.directoryURL = preferredStartDirectory(for: item)

        if panel.runModal() == .OK, let url = panel.url {
            guard let idx = itemIndex else { return }
            appState.queuedItems[idx].manualTargetPath = url.path
            appState.queuedItems[idx].needsPathConfirmation = false
            appState.queuedItems[idx].previewPath = url.lastPathComponent

            if let project = appState.queuedItems[idx].targetProject {
                let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
                if let relative = PathResolver.shared.makeRelativeToProject(url.path, project: project) {
                    PathLearningManager.shared.recordPathDecision(
                        projectPath: project.projectPath,
                        assetType: appState.queuedItems[idx].predictedType,
                        subfolder: appState.queuedItems[idx].targetSubfolder,
                        chosenPath: relative,
                        fileExtension: ext,
                        source: appState.queuedItems[idx].detectedSource
                    )
                }
            }
        }
    }

    /// Bepaal de slimste startmap voor de folder picker:
    /// 1. targetPath als die onder het project valt (refine bestaande keuze)
    /// 2. Anders project main folder
    /// 3. Anders nil (system default)
    private func preferredStartDirectory(for item: DownloadItem) -> URL? {
        let project = item.targetProject

        if let path = item.targetPath ?? item.manualTargetPath {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            if let project = project {
                let projectRoot = PathResolver.shared.projectMainFolderURL(for: project).path
                if parent.path.hasPrefix(projectRoot) {
                    return parent
                }
            } else {
                return parent
            }
        }

        if let project = project {
            return PathResolver.shared.projectMainFolderURL(for: project)
        }

        return nil
    }
}
