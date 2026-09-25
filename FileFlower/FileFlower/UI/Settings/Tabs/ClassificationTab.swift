import SwiftUI

struct ClassificationTabView: View {
    @Binding var musicMode: MusicMode
    @Binding var useSfxSubfolders: Bool
    @Binding var useClaudeClassification: Bool
    @Binding var claudeAPIKey: String
    @Binding var claudeConnectionStatus: ClaudeConnectionStatus
    @Binding var useGenreMoodDetection: Bool
    @Binding var useWebScraping: Bool

    private var previewItems: [String] {
        let source = musicMode == .mood ? MoodList.shared.moods : GenreList.shared.genres
        return Array(source.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Music classification
            SettingsCard(
                title: String(localized: "settings.card.music_classification"),
                desc: String(localized: "settings.card.music_classification.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.classification.mode"),
                    help: String(localized: "settings.classification.mode.help"),
                    isFirst: true
                ) {
                    Picker("", selection: $musicMode) {
                        Text(String(localized: "common.mood")).tag(MusicMode.mood)
                        Text(String(localized: "common.genre")).tag(MusicMode.genre)
                    }
                    .pickerStyle(.segmented)
                    .tint(.brandBurntPeach)
                    .frame(width: 200)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.classification.live_preview").uppercased())
                        .font(.brandMono(size: 10.5, weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(.ink3)

                    TreePreview(
                        rootName: "03_Music",
                        entries: previewItems,
                        highlightedIndices: Set(0..<previewItems.count)
                    )
                    .id(musicMode)
                    .transition(.opacity)
                }
                .padding(.top, 12)
            }

            // SFX subfolders
            SettingsCard(
                title: String(localized: "settings.card.sfx_subfolders"),
                desc: String(localized: "settings.card.sfx_subfolders.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.sfx_subfolders.label"),
                    help: String(localized: "settings.sfx_subfolders.help"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $useSfxSubfolders)
                }
            }

            // Smart classification (Claude)
            SettingsCard(
                title: String(localized: "settings.card.smart_classification"),
                desc: String(localized: "settings.card.smart_classification.desc"),
                kicker: String(localized: "settings.kicker.optional")
            ) {
                SettingsRow(
                    label: String(localized: "settings.use_claude"),
                    help: String(localized: "settings.use_claude.help"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $useClaudeClassification)
                }

                if useClaudeClassification {
                    SettingsRow(
                        label: String(localized: "settings.api_key"),
                        help: String(localized: "settings.api_key.keychain_help")
                    ) {
                        HStack(spacing: 6) {
                            SecureField("sk-ant-…", text: $claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .font(.brandMono(size: 11.5))
                                .frame(width: 200)

                            BrandButton(title: claudeButtonLabel,
                                        variant: .secondary,
                                        size: .regular,
                                        action: testConnection)
                                .disabled(claudeAPIKey.isEmpty)
                        }
                    }
                }
            }

            // Source detection
            SettingsCard(
                title: String(localized: "settings.card.source_detection"),
                desc: String(localized: "settings.card.source_detection.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.web_scraping"),
                    help: String(localized: "settings.web_scraping_description"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $useWebScraping)
                }
            }
        }
    }

    private var claudeButtonLabel: String {
        switch claudeConnectionStatus {
        case .testing: return String(localized: "settings.connection.testing")
        case .connected: return "✓ " + String(localized: "settings.connection.connected")
        case .failed: return "✕ Test"
        case .unknown: return String(localized: "settings.test_connection")
        }
    }

    private func testConnection() {
        claudeConnectionStatus = .testing
        Task {
            let success = await ClaudeClassificationStrategy.testConnection(apiKey: claudeAPIKey)
            await MainActor.run {
                claudeConnectionStatus = success ? .connected : .failed("Connection failed")
            }
        }
    }
}
