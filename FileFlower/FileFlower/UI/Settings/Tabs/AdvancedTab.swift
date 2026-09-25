import SwiftUI

struct AdvancedTabView: View {
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // File locations
            SettingsCard(
                title: String(localized: "settings.card.file_locations"),
                desc: String(localized: "settings.card.file_locations.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.file_locations.config"),
                    help: configPathHelp,
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.file_locations.reveal"),
                                variant: .secondary, size: .regular) {
                        revealConfig()
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.file_locations.logs"),
                    help: String(localized: "settings.file_locations.logs.help")
                ) {
                    BrandButton(title: String(localized: "settings.file_locations.console"),
                                variant: .secondary, size: .regular) {
                        if let url = URL(string: "/System/Applications/Utilities/Console.app") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            // Setup
            SettingsCard(
                title: "Setup",
                desc: String(localized: "settings.card.setup.desc"),
                kicker: String(localized: "settings.kicker.careful")
            ) {
                SettingsRow(
                    label: String(localized: "settings.setup.resume_onboarding"),
                    help: String(localized: "settings.setup.resume_onboarding.help"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.setup.resume"),
                                variant: .secondary, size: .regular) {
                        OnboardingWindowController.show {}
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.setup.reset_all"),
                    help: String(localized: "settings.setup.reset_all.help")
                ) {
                    BrandButton(title: String(localized: "settings.setup.reset_button") + "…",
                                variant: .danger, size: .regular) {
                        showResetConfirmation = true
                    }
                }
            }
        }
        .alert(String(localized: "settings.reset_setup_title"), isPresented: $showResetConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "settings.reset"), role: .destructive) {
                SetupManager.shared.resetOnboarding()
                OnboardingWindowController.show {}
            }
        } message: {
            Text(String(localized: "settings.reset_setup_message"))
        }
    }

    private var configPathHelp: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("FileFlower").path ?? "—"
        return "config.json · \(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
    }

    private func revealConfig() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("FileFlower")
        if let dir = dir {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        }
    }
}
