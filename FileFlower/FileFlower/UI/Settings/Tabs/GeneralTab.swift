import SwiftUI

struct GeneralTabView: View {
    @Binding var appLanguage: String
    @Binding var showPopupAfterDownload: Bool
    @Binding var showPetalAnimation: Bool
    @Binding var autoOpenBridgePanel: Bool
    @Binding var startAtLogin: Bool
    @Binding var filterServerProjectsToLocal: Bool
    @Binding var autoAddActiveProjectRoot: Bool
    @Binding var analyticsEnabled: Bool
    let onSave: () -> Void

    private let languages: [(code: String, name: String, flag: String)] = [
        ("en", "English", "🇬🇧"),
        ("nl", "Nederlands", "🇳🇱"),
        ("de", "Deutsch", "🇩🇪"),
        ("fr", "Français", "🇫🇷"),
        ("es", "Español", "🇪🇸")
    ]

    var body: some View {
        VStack(spacing: 0) {
            SettingsCard(
                title: String(localized: "settings.card.language"),
                desc: String(localized: "settings.card.language.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.language"),
                    help: String(localized: "settings.language.restart_needed"),
                    isFirst: true
                ) {
                    Picker("", selection: $appLanguage) {
                        ForEach(languages, id: \.code) { lang in
                            Text("\(lang.flag) \(lang.name)").tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                    .labelsHidden()
                }
            }

            SettingsCard(
                title: String(localized: "settings.card.on_download"),
                desc: String(localized: "settings.card.on_download.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.show_popup"),
                    help: String(localized: "settings.show_popup.desc"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $showPopupAfterDownload)
                }
                SettingsRow(
                    label: String(localized: "settings.petal_animation"),
                    help: String(localized: "settings.petal_animation.desc")
                ) {
                    BrandToggle(isOn: $showPetalAnimation)
                }
                SettingsRow(
                    label: String(localized: "settings.auto_open_bridge"),
                    help: String(localized: "settings.auto_open_bridge.desc")
                ) {
                    BrandToggle(isOn: $autoOpenBridgePanel)
                }
            }

            SettingsCard(
                title: String(localized: "settings.card.on_startup"),
                desc: String(localized: "settings.card.on_startup.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.start_at_login"),
                    help: String(localized: "settings.start_at_login.desc"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $startAtLogin)
                }
            }

            SettingsCard(
                title: String(localized: "settings.card.project_behavior"),
                desc: String(localized: "settings.card.project_behavior.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.filter_server_projects"),
                    help: String(localized: "settings.filter_server_projects.description"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $filterServerProjectsToLocal)
                }
                SettingsRow(
                    label: String(localized: "settings.auto_add_project_root"),
                    help: String(localized: "settings.auto_add_project_root.description")
                ) {
                    BrandToggle(isOn: $autoAddActiveProjectRoot)
                }
            }

            SettingsCard(
                title: String(localized: "settings.card.privacy"),
                desc: String(localized: "settings.card.privacy.desc"),
                kicker: String(localized: "settings.kicker.anonymous")
            ) {
                SettingsRow(
                    label: String(localized: "settings.analytics"),
                    help: String(localized: "settings.analytics.description"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $analyticsEnabled)
                }
            }

            // Gids — bewust hier en niet bij Geavanceerd, waar de destructieve
            // "Reset setup" staat. De gids raakt de configuratie niet aan.
            SettingsCard(
                title: String(localized: "settings.help"),
                desc: String(localized: "settings.card.help.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.open_guide"),
                    help: String(localized: "settings.open_guide_description"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.open_guide_button"),
                                variant: .secondary, size: .regular) {
                        GuideWindowController.show()
                    }
                }
            }
        }
    }
}
