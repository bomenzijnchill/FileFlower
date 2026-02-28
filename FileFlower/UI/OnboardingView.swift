import SwiftUI
import AppKit

/// Multi-step onboarding wizard voor eerste setup
struct OnboardingView: View {
    @StateObject private var appState = AppState.shared
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var projectRoot: String = ""
    @State private var isScanning = false
    @State private var chromeInstructionsExpanded = true
    @State private var isValidatingExtension = false
    @State private var extensionMarkedInstalled = false
    @State private var extensionServerRunning = false
    @State private var selectedBrowser: String = "chrome"
    @State private var finderExtensionEnabled = false
    @State private var isCheckingFinderExtension = false

    // Nieuwe wizard state
    @State private var selectedLanguage: String = "en"
    @State private var wizardLocale: Locale = Locale(identifier: "en")
    @State private var musicClassifyEnabled: Bool = true
    @State private var musicMode: MusicMode = .mood
    @State private var sfxSubfoldersEnabled: Bool = true
    @State private var autoStartEnabled: Bool = true
    @State private var termsAccepted: Bool = false
    @State private var analyticsOptIn: Bool = false
    @State private var savesFilesNextToProject: Bool = true
    @State private var selectedWorkflowType: WorkflowType = .videoEditor
    @State private var selectedFolderStructure: FolderStructurePreset = .standard

    // Custom folder template state
    @State private var templateFolderPath: String = ""
    @State private var scannedFolderTree: FolderNode?
    @State private var isScanningTemplate = false
    @State private var isAnalyzingTemplate = false
    @State private var templateMapping: FolderTypeMapping?
    @State private var templateError: String?

    let onComplete: () -> Void

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case language = 1
        case musicClassify = 2
        case sfxSubfolders = 3
        case premierePlugin = 4
        case resolveSetup = 5
        case chromeExtension = 6
        case finderExtension = 7
        case projectSetup = 8
        case workflow = 9
        case autoStart = 10
        case terms = 11
        case complete = 12

        var titleKey: String.LocalizationValue {
            switch self {
            case .welcome: return "onboarding.welcome.title"
            case .language: return "onboarding.language.title"
            case .musicClassify: return "onboarding.music.title"
            case .sfxSubfolders: return "onboarding.sfx.title"
            case .premierePlugin: return "onboarding.premiere.title"
            case .resolveSetup: return "onboarding.resolve.title"
            case .chromeExtension: return "onboarding.chrome.title"
            case .finderExtension: return "onboarding.finder.title"
            case .projectSetup: return "onboarding.project.title"
            case .workflow: return "onboarding.workflow.title"
            case .autoStart: return "onboarding.autostart.title"
            case .terms: return "onboarding.terms.title"
            case .complete: return "onboarding.complete.title"
            }
        }

        func title(locale: Locale) -> String {
            return String(localized: titleKey, locale: locale)
        }

        var icon: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .language: return "globe"
            case .musicClassify: return "music.note.list"
            case .sfxSubfolders: return "speaker.wave.3.fill"
            case .premierePlugin: return "film.fill"
            case .resolveSetup: return "film.stack.fill"
            case .chromeExtension: return "globe"
            case .finderExtension: return "folder.badge.plus"
            case .projectSetup: return "folder.fill"
            case .workflow: return "hammer.fill"
            case .autoStart: return "power"
            case .terms: return "doc.text.fill"
            case .complete: return "checkmark.circle.fill"
            }
        }
    }

    // Beschikbare talen
    struct AppLanguage: Identifiable {
        let id: String // taalcode
        let name: String
        let flag: String
    }

    let availableLanguages: [AppLanguage] = [
        AppLanguage(id: "en", name: "English", flag: "🇬🇧"),
        AppLanguage(id: "nl", name: "Nederlands", flag: "🇳🇱"),
        AppLanguage(id: "de", name: "Deutsch", flag: "🇩🇪"),
        AppLanguage(id: "fr", name: "Français", flag: "🇫🇷"),
        AppLanguage(id: "es", name: "Español", flag: "🇪🇸")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 24)
                .padding(.horizontal, 32)

            // Content
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity)
                    .padding(32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 600, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
        .environment(\.locale, wizardLocale)
        .onAppear {
            // Start wizard altijd in het Engels
            selectedLanguage = "en"
            wizardLocale = Locale(identifier: "en")
            musicClassifyEnabled = appState.config.useGenreMoodDetection
            musicMode = appState.config.musicClassification
            sfxSubfoldersEnabled = appState.config.useSfxSubfolders
            autoStartEnabled = appState.config.startAtLogin
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                if step != .complete {
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)

                    if step.rawValue < OnboardingStep.allCases.count - 2 {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: 24)
                    }
                }
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeContent
        case .language:
            languageContent
        case .musicClassify:
            musicClassifyContent
        case .sfxSubfolders:
            sfxSubfoldersContent
        case .premierePlugin:
            premierePluginContent
        case .resolveSetup:
            resolveSetupContent
        case .chromeExtension:
            chromeExtensionContent
        case .finderExtension:
            finderExtensionContent
        case .projectSetup:
            projectSetupContent
        case .workflow:
            workflowContent
        case .autoStart:
            autoStartContent
        case .terms:
            termsContent
        case .complete:
            completeContent
        }
    }

    // MARK: - Welcome Step

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Image("FileFlowerLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)

            Text(String(localized: "onboarding.welcome.title"))
                .font(.system(size: 28, weight: .bold))

            Text(String(localized: "onboarding.welcome.subtitle"))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "arrow.down.doc.fill",
                           title: String(localized: "onboarding.welcome.feature.detection.title"),
                           description: String(localized: "onboarding.welcome.feature.detection.description"))
                FeatureRow(icon: "folder.fill.badge.plus",
                           title: String(localized: "onboarding.welcome.feature.organization.title"),
                           description: String(localized: "onboarding.welcome.feature.organization.description"))
                FeatureRow(icon: "film.fill",
                           title: String(localized: "onboarding.welcome.feature.premiere.title"),
                           description: String(localized: "onboarding.welcome.feature.premiere.description"))
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Language Step

    private var languageContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundColor(.brandSkyBlue)

            Text(String(localized: "onboarding.language.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.language.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 8) {
                ForEach(availableLanguages) { lang in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLanguage = lang.id
                            wizardLocale = Locale(identifier: lang.id)
                        }
                    }) {
                        HStack(spacing: 16) {
                            Text(lang.flag)
                                .font(.system(size: 28))

                            Text(lang.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedLanguage == lang.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedLanguage == lang.id ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedLanguage == lang.id ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 350)
        }
    }

    // MARK: - Music Classification Step

    private var musicClassifyContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.brandBurntPeach)

            Text(String(localized: "onboarding.music.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.music.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 16) {
                Toggle(String(localized: "onboarding.music.auto_sort"), isOn: $musicClassifyEnabled)
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                if musicClassifyEnabled {
                    VStack(spacing: 12) {
                        HStack {
                            Text(String(localized: "onboarding.music.sort_by"))
                                .font(.system(size: 14, weight: .medium))

                            Spacer()

                            Picker("", selection: $musicMode) {
                                Text(String(localized: "common.mood")).tag(MusicMode.mood)
                                Text(String(localized: "common.genre")).tag(MusicMode.genre)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        // Folder preview
                        folderPreview(
                            rootName: "01_Music",
                            subfolders: musicMode == .mood
                                ? ["Happy", "Dark", "Epic", "Peaceful"]
                                : ["EDM", "Hip Hop", "Rock", "Cinematic"]
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: 400)
            .animation(.easeInOut(duration: 0.3), value: musicClassifyEnabled)
        }
    }

    // MARK: - SFX Subfolders Step

    private var sfxSubfoldersContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 60))
                .foregroundColor(.brandSandyClay)

            Text(String(localized: "onboarding.sfx.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.sfx.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 16) {
                Toggle(String(localized: "onboarding.sfx.auto_sort"), isOn: $sfxSubfoldersEnabled)
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                if sfxSubfoldersEnabled {
                    folderPreview(
                        rootName: "04_SFX",
                        subfolders: ["Impacts", "Swooshes", "Foley", "Ambience"]
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: 400)
            .animation(.easeInOut(duration: 0.3), value: sfxSubfoldersEnabled)
        }
    }

    // MARK: - Premiere Plugin Step

    private var premierePluginContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "film.fill")
                .font(.system(size: 60))
                .foregroundColor(.brandBurntPeach)

            Text(String(localized: "onboarding.premiere.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.premiere.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 16) {
                // Status
                HStack(spacing: 12) {
                    if SetupManager.shared.isPremierePluginInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 24))
                        Text(String(localized: "onboarding.premiere.installed"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 24))
                        Text(String(localized: "onboarding.premiere.not_installed"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Error message
                if let error = installError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                // Install button
                if !SetupManager.shared.isPremierePluginInstalled {
                    Button(action: installPremierePlugin) {
                        HStack(spacing: 8) {
                            if isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(isInstalling
                                 ? String(localized: "onboarding.premiere.installing")
                                 : String(localized: "onboarding.premiere.install_button"))
                        }
                        .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isInstalling)
                }
            }

            Text(String(localized: "onboarding.premiere.restart_note"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    // MARK: - DaVinci Resolve Setup Step

    private var resolveSetupContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 60))
                .foregroundColor(.brandSkyBlue)

            Text(String(localized: "onboarding.resolve.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.resolve.description"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                // Python 3 check
                HStack(spacing: 12) {
                    Image(systemName: SetupManager.shared.isPython3Available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(SetupManager.shared.isPython3Available ? .green : .orange)
                        .font(.system(size: 20))
                    VStack(alignment: .leading) {
                        Text("Python 3")
                            .font(.system(size: 13, weight: .semibold))
                        Text(SetupManager.shared.isPython3Available
                             ? String(localized: "onboarding.resolve.python_found")
                             : String(localized: "onboarding.resolve.python_not_found"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Resolve scripting modules check
                HStack(spacing: 12) {
                    Image(systemName: SetupManager.shared.isResolveScriptingAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(SetupManager.shared.isResolveScriptingAvailable ? .green : .orange)
                        .font(.system(size: 20))
                    VStack(alignment: .leading) {
                        Text("DaVinci Resolve Scripting API")
                            .font(.system(size: 13, weight: .semibold))
                        Text(SetupManager.shared.isResolveScriptingAvailable
                             ? String(localized: "onboarding.resolve.scripting_found")
                             : String(localized: "onboarding.resolve.scripting_not_found"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            Text(String(localized: "onboarding.resolve.skip_note"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    // MARK: - Browser Extension Step

    private var chromeExtensionContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundColor(.brandSkyBlue)

            Text(String(localized: "onboarding.chrome.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.chrome.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Browser keuze
            HStack(spacing: 12) {
                browserChoiceButton(
                    browser: "chrome",
                    icon: "globe",
                    label: "Chrome"
                )
                browserChoiceButton(
                    browser: "safari",
                    icon: "safari",
                    label: "Safari"
                )
            }
            .padding(.top, 4)

            if selectedBrowser == "chrome" {
                chromeInstructions
            } else {
                safariInstructions
            }

            extensionStatusIndicator
        }
    }

    private func browserChoiceButton(browser: String, icon: String, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedBrowser = browser
                extensionMarkedInstalled = false
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 100, height: 70)
            .background(selectedBrowser == browser ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedBrowser == browser ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var chromeInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(
                isExpanded: $chromeInstructionsExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionStep(number: 1, text: String(localized: "onboarding.chrome.step1"))
                        InstructionStep(number: 2, text: String(localized: "onboarding.chrome.step2"))
                        InstructionStep(number: 3, text: String(localized: "onboarding.chrome.step3"))

                        VStack(alignment: .leading, spacing: 4) {
                            Button(action: {
                                SetupManager.shared.openChromeExtensionFolder()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                    Text(String(localized: "onboarding.chrome.open_folder"))
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Text(String(localized: "onboarding.chrome.folder_hint"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 36)

                        InstructionStep(number: 4, text: String(localized: "onboarding.chrome.step4"))
                    }
                    .padding(.top, 12)
                },
                label: {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.brandSkyBlue)
                        Text(String(localized: "onboarding.chrome.instructions"))
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            )
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .frame(maxWidth: 450)
        .transition(.opacity)
    }

    private var safariInstructions: some View {
        VStack(spacing: 16) {
            Button(action: {
                SetupManager.shared.openSafariExtensionApp()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                    Text(String(localized: "onboarding.safari.install_button"))
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text(String(localized: "onboarding.safari.install_hint"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .transition(.opacity)
    }

    private var extensionStatusIndicator: some View {
        Group {
            if isValidatingExtension {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "onboarding.chrome.checking"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            } else if extensionMarkedInstalled {
                HStack(spacing: 8) {
                    Image(systemName: extensionServerRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(extensionServerRunning ? .green : .orange)
                    Text(extensionServerRunning
                         ? String(localized: "onboarding.chrome.marked_installed")
                         : String(localized: "onboarding.chrome.marked_no_server"))
                        .font(.system(size: 13))
                        .foregroundColor(extensionServerRunning ? .green : .orange)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .scale))
            } else {
                Button(action: validateAndMarkExtensionInstalled) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                        Text(String(localized: "onboarding.chrome.confirm_installed"))
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Finder Extension Step

    private var finderExtensionContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.brandSandyClay)

            Text(String(localized: "onboarding.finder.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.finder.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    InstructionStep(number: 1, text: String(localized: "onboarding.finder.step1"))
                    InstructionStep(number: 2, text: String(localized: "onboarding.finder.step2"))
                    InstructionStep(number: 3, text: String(localized: "onboarding.finder.step3"))
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .frame(maxWidth: 450)

            Button(action: {
                SetupManager.shared.openFinderExtensionSettings()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                    Text(String(localized: "onboarding.finder.open_settings"))
                }
            }
            .buttonStyle(.borderedProminent)

            // Status indicator
            Group {
                if isCheckingFinderExtension {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "onboarding.finder.checking"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else if finderExtensionEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(String(localized: "onboarding.finder.enabled"))
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                    }
                } else {
                    Button(action: checkFinderExtensionStatus) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text(String(localized: "onboarding.finder.check_status"))
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            checkFinderExtensionStatus()
        }
    }

    private func checkFinderExtensionStatus() {
        isCheckingFinderExtension = true
        DispatchQueue.global(qos: .userInitiated).async {
            let enabled = SetupManager.shared.isFinderExtensionEnabled()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    finderExtensionEnabled = enabled
                    isCheckingFinderExtension = false
                }
            }
        }
    }

    // MARK: - Project Setup Step

    private var projectSetupContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.brandSandyClay)

            Text(String(localized: "onboarding.project.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.project.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField(String(localized: "onboarding.project.folder_field"), text: $projectRoot)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Button(String(localized: "common.browse")) {
                        selectProjectRoot()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 400)

                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "onboarding.project.scanning"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else if !projectRoot.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(String(localized: "onboarding.project.folder_selected"))
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                    }
                }

                Text(String(localized: "onboarding.project.add_later"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Workflow Step

    private var workflowContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 60))
                .foregroundColor(.brandSkyBlue)

            Text(String(localized: "onboarding.workflow.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.workflow.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 16) {
                // Vraag 1: Bestanden naast project opslaan?
                Toggle(String(localized: "onboarding.workflow.files_next_to_project"), isOn: $savesFilesNextToProject)
                    .toggleStyle(.switch)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                // Vraag 2: Wat voor werk doe je?
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "onboarding.workflow.type_label"))
                        .font(.system(size: 13, weight: .medium))

                    ForEach(WorkflowType.allCases, id: \.self) { type in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedWorkflowType = type
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .frame(width: 20)
                                Text(String(localized: type.displayKey))
                                    .font(.system(size: 14))
                                Spacer()
                                if selectedWorkflowType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedWorkflowType == type ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Vraag 3: Mappenstructuur
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "onboarding.workflow.folder_label"))
                        .font(.system(size: 13, weight: .medium))

                    ForEach(FolderStructurePreset.allCases, id: \.self) { preset in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedFolderStructure = preset
                            }
                        }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: preset.displayKey))
                                        .font(.system(size: 14, weight: .medium))
                                    Text(String(localized: preset.descriptionKey))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedFolderStructure == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedFolderStructure == preset ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Uitklapbare custom template sectie
                    if selectedFolderStructure == .custom {
                        customFolderTemplateSection
                    }
                }
            }
            .frame(maxWidth: 400)
        }
    }

    // MARK: - Custom Folder Template

    private var customFolderTemplateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Map selectie knop
            HStack {
                Image(systemName: "folder.badge.plus")
                    .foregroundColor(.secondary)
                Text(templateFolderPath.isEmpty
                     ? String(localized: "onboarding.template.no_folder")
                     : URL(fileURLWithPath: templateFolderPath).lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(templateFolderPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(String(localized: "onboarding.template.select_folder")) {
                    selectTemplateFolder()
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            // Scanning indicator
            if isScanningTemplate {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "onboarding.template.scanning"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }

            // Boom preview
            if let tree = scannedFolderTree, !isScanningTemplate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "onboarding.template.preview_title"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            let flatItems = flattenTree(tree)
                            ForEach(Array(flatItems.enumerated()), id: \.offset) { _, item in
                                folderTreeRow(item.node, depth: item.depth)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                }
            }

            // AI analyse indicator
            if isAnalyzingTemplate {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "onboarding.template.analyzing"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }

            // Mapping resultaat
            if let mapping = templateMapping, !isAnalyzingTemplate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "onboarding.template.mapping_title"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        mappingRow("Music", path: mapping.musicPath)
                        mappingRow("SFX", path: mapping.sfxPath)
                        mappingRow("Voice Over", path: mapping.voPath)
                        mappingRow("Graphics", path: mapping.graphicsPath)
                        mappingRow("Motion Graphics", path: mapping.motionGraphicsPath)
                        mappingRow("Stock Footage", path: mapping.stockFootagePath)
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)

                    if let desc = mapping.description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }

            // Error
            if let error = templateError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 4)

                Button(String(localized: "onboarding.template.retry")) {
                    retryTemplateAnalysis()
                }
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Flatten de boom naar een lijst van (node, depth) tuples voor niet-recursieve rendering
    private func flattenTree(_ node: FolderNode, depth: Int = 0) -> [(node: FolderNode, depth: Int)] {
        var result = [(node: node, depth: depth)]
        for child in node.children {
            result += flattenTree(child, depth: depth + 1)
        }
        return result
    }

    private func folderTreeRow(_ node: FolderNode, depth: Int) -> some View {
        HStack(spacing: 4) {
            Text(String(repeating: "  ", count: depth))
                .font(.system(size: 11, design: .monospaced))
            Image(systemName: depth == 0 ? "folder.fill" : "folder")
                .foregroundColor(depth == 0 ? .accentColor : .secondary)
                .font(.system(size: 10))
            Text(node.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(depth == 0 ? .primary : .secondary)
        }
    }

    private func mappingRow(_ label: String, path: String?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 100, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(path ?? String(localized: "onboarding.template.not_detected"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(path != nil ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func selectTemplateFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "onboarding.template.panel_message")

        if panel.runModal() == .OK, let url = panel.url {
            templateFolderPath = url.path
            templateError = nil
            templateMapping = nil
            isScanningTemplate = true

            Task {
                // Stap 1: Scan
                let tree = FolderTemplateService.shared.scanFolderTree(at: url)
                await MainActor.run {
                    scannedFolderTree = tree
                    isScanningTemplate = false
                    isAnalyzingTemplate = true
                }

                // Stap 2: AI Analyse
                do {
                    let mapping = try await FolderTemplateService.shared.analyzeStructure(
                        tree: tree,
                        deviceId: appState.config.anonymousId
                    )
                    await MainActor.run {
                        templateMapping = mapping
                        isAnalyzingTemplate = false
                    }
                } catch {
                    await MainActor.run {
                        templateError = error.localizedDescription
                        isAnalyzingTemplate = false
                    }
                }
            }
        }
    }

    private func retryTemplateAnalysis() {
        guard let tree = scannedFolderTree else { return }
        templateError = nil
        isAnalyzingTemplate = true

        Task {
            do {
                let mapping = try await FolderTemplateService.shared.analyzeStructure(
                    tree: tree,
                    deviceId: appState.config.anonymousId
                )
                await MainActor.run {
                    templateMapping = mapping
                    isAnalyzingTemplate = false
                }
            } catch {
                await MainActor.run {
                    templateError = error.localizedDescription
                    isAnalyzingTemplate = false
                }
            }
        }
    }

    // MARK: - Auto Start Step

    private var autoStartContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "power")
                .font(.system(size: 60))
                .foregroundColor(.brandSkyBlue)

            Text(String(localized: "onboarding.autostart.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.autostart.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Toggle(String(localized: "onboarding.autostart.toggle"), isOn: $autoStartEnabled)
                .toggleStyle(.switch)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 400)
        }
    }

    // MARK: - Terms & Conditions Step

    private var termsContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 50))
                .foregroundColor(.brandSandyClay)

            Text(String(localized: "onboarding.terms.title"))
                .font(.system(size: 24, weight: .bold))

            // Scrollable terms content
            ScrollView {
                Text(loadTermsText())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: 480, maxHeight: 180)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $termsAccepted) {
                    Text(String(localized: "onboarding.terms.accept"))
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $analyticsOptIn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "onboarding.terms.analytics"))
                            .font(.system(size: 13))
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(maxWidth: 480, alignment: .leading)
        }
    }

    // MARK: - Complete Step

    private var completeContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Image("FileFlowerLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color(NSColor.windowBackgroundColor)).frame(width: 24, height: 24))
                    .offset(x: 32, y: 32)
            }

            Text(String(localized: "onboarding.complete.title"))
                .font(.system(size: 28, weight: .bold))

            Text(String(localized: "onboarding.complete.subtitle"))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                CompletionCheckItem(
                    isCompleted: SetupManager.shared.isPremierePluginInstalled,
                    text: String(localized: "onboarding.complete.premiere_check")
                )
                CompletionCheckItem(
                    isCompleted: SetupManager.shared.installedChromeExtensionVersion != nil,
                    text: String(localized: "onboarding.complete.chrome_check")
                )
                CompletionCheckItem(
                    isCompleted: finderExtensionEnabled,
                    text: String(localized: "onboarding.complete.finder_check")
                )
                CompletionCheckItem(
                    isCompleted: !appState.config.projectRoots.isEmpty,
                    text: String(localized: "onboarding.complete.project_check")
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text(String(localized: "onboarding.complete.restart_premiere"))
                .font(.system(size: 13))
                .foregroundColor(.orange)
                .padding(.top, 8)
        }
    }

    // MARK: - Helper Views

    private func folderPreview(rootName: String, subfolders: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                Text(rootName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }

            ForEach(subfolders, id: \.self) { folder in
                HStack(spacing: 6) {
                    Text("  ")
                    Image(systemName: "folder.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Text(folder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button(String(localized: "common.previous")) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = previous
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep == .complete {
                Button(String(localized: "start_fileflower")) {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(nextButtonTitle) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        goToNextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            }
        }
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case .premierePlugin:
            return SetupManager.shared.isPremierePluginInstalled
                ? String(localized: "common.next")
                : String(localized: "common.skip")
        case .resolveSetup:
            return String(localized: "common.next")
        case .chromeExtension:
            return String(localized: "common.next")
        case .finderExtension:
            return String(localized: "common.next")
        case .projectSetup:
            return projectRoot.isEmpty
                ? String(localized: "common.skip")
                : String(localized: "common.next")
        default:
            return String(localized: "common.next")
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .premierePlugin:
            return !isInstalling
        case .terms:
            return termsAccepted
        default:
            return true
        }
    }

    // MARK: - Actions

    private func goToNextStep() {
        // Sla instellingen op per stap
        switch currentStep {
        case .language:
            appState.config.appLanguage = selectedLanguage
            appState.saveConfig()
            // Sla taalvoorkeur op in UserDefaults voor volgende keer
            UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()

        case .musicClassify:
            appState.config.useGenreMoodDetection = musicClassifyEnabled
            appState.config.musicClassification = musicMode
            appState.saveConfig()

        case .sfxSubfolders:
            appState.config.useSfxSubfolders = sfxSubfoldersEnabled
            appState.saveConfig()

        case .projectSetup:
            // Project root wordt al toegevoegd in selectProjectRoot()
            break

        case .workflow:
            appState.config.savesFilesNextToProject = savesFilesNextToProject
            appState.config.userWorkflowType = selectedWorkflowType
            appState.config.folderStructurePreset = selectedFolderStructure

            // Sla custom folder template op als .custom geselecteerd en analyse voltooid
            if selectedFolderStructure == .custom,
               let tree = scannedFolderTree,
               let mapping = templateMapping {
                appState.config.customFolderTemplate = CustomFolderTemplate(
                    sourcePath: templateFolderPath,
                    folderTree: tree,
                    mapping: mapping,
                    createdAt: Date(),
                    lastUpdatedAt: Date()
                )
            }
            appState.saveConfig()

        case .autoStart:
            appState.config.startAtLogin = autoStartEnabled
            appState.saveConfig()
            if autoStartEnabled {
                try? LaunchAgentManager.shared.enableStartAtLogin()
            } else {
                try? LaunchAgentManager.shared.disableStartAtLogin()
            }

        case .terms:
            appState.config.termsAcceptedVersion = "1.0"
            appState.config.termsAcceptedDate = Date()
            appState.config.analyticsEnabled = analyticsOptIn
            appState.saveConfig()
            // Markeer wizard als voltooid zodra terms geaccepteerd zijn
            // zodat een herstart de wizard niet heropent
            SetupManager.shared.completeOnboarding()

        default:
            break
        }

        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    private func validateAndMarkExtensionInstalled() {
        isValidatingExtension = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let serverRunning = JobServer.shared.isServerRunning

            withAnimation(.easeInOut(duration: 0.3)) {
                isValidatingExtension = false
                extensionServerRunning = serverRunning
                extensionMarkedInstalled = true
            }

            SetupManager.shared.selectedBrowser = selectedBrowser
            SetupManager.shared.markChromeExtensionInstalled()
        }
    }

    private func installPremierePlugin() {
        isInstalling = true
        installError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SetupManager.shared.installPremierePlugin()

            DispatchQueue.main.async {
                isInstalling = false

                switch result {
                case .success:
                    installError = nil
                case .failure(let error):
                    installError = error.localizedDescription
                }
            }
        }
    }

    private func selectProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "onboarding.project.subtitle")

        if panel.runModal() == .OK, let url = panel.url {
            projectRoot = url.path
            // Scan projecten async met progress indicator
            isScanning = true
            Task {
                if !appState.config.projectRoots.contains(url.path) {
                    appState.config.projectRoots.append(url.path)
                    appState.saveConfig()
                }
                await appState.refreshRecentProjects()
                isScanning = false
            }
        }
    }

    private func finishOnboarding() {
        SetupManager.shared.completeOnboarding()
        onComplete()
    }

    private func loadTermsText() -> String {
        // Probeer terms_and_conditions.md te laden uit de bundle
        if let url = Bundle.main.url(forResource: "terms_and_conditions", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }

        // Fallback tekst
        return """
        FileFlower Terms & Conditions (v1.0)

        1. ACCEPTANCE OF TERMS
        By using FileFlower, you agree to these terms and conditions.

        2. LICENSE & USAGE
        FileFlower is licensed per user through Gumroad. One license may be used on up to 2 devices.

        3. TRIAL PERIOD
        FileFlower offers a 7-day free trial. After the trial period, a valid license key is required.

        4. PRIVACY & DATA COLLECTION
        FileFlower collects minimal data:
        - License validation via Gumroad (email address)
        - Update checks via GitHub (no personal data)
        - Anonymous usage statistics (only if you opt in)

        No file names, file paths, or personal content is ever collected or transmitted.

        5. INTELLECTUAL PROPERTY
        FileFlower and all associated components are the intellectual property of the developer.

        6. LIABILITY & DISCLAIMER
        FileFlower is provided "as is" without warranty. The developer is not liable for any data loss or damage resulting from the use of this software.

        7. CHANGES TO TERMS
        These terms may be updated. Users will be notified of significant changes.

        8. CONTACT
        For questions about these terms, please contact support.
        """
    }
}

// MARK: - Helper Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 13))
        }
    }
}

struct CompletionCheckItem: View {
    let isCompleted: Bool
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .secondary)
                .font(.system(size: 18))

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(isCompleted ? .primary : .secondary)
        }
    }
}

// MARK: - Window Controller

class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static var windowController: NSWindowController?
    private static var delegate: OnboardingWindowController?
    private var onCompleteHandler: (() -> Void)?

    static func show(onComplete: @escaping () -> Void) {
        // Sluit bestaand window als dat er is
        windowController?.close()

        // Toon dock-icoon zodat de wizard zichtbaar is via cmd+tab
        NSApplication.shared.setActivationPolicy(.regular)

        let delegateInstance = OnboardingWindowController()
        delegateInstance.onCompleteHandler = onComplete
        delegate = delegateInstance

        let onboardingView = OnboardingView(onComplete: {
            windowController?.close()
            windowController = nil
            delegate = nil
            // Verberg dock-icoon weer (terug naar menu bar only)
            NSApplication.shared.setActivationPolicy(.accessory)
            onComplete()
        })

        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "FileFlower Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 600, height: 650))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = delegateInstance

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        // Breng window naar voren
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close() {
        windowController?.close()
        windowController = nil
        delegate = nil
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Verberg dock-icoon wanneer wizard gesloten wordt via rode X
        NSApplication.shared.setActivationPolicy(.accessory)
        OnboardingWindowController.windowController = nil
        OnboardingWindowController.delegate = nil
    }
}
