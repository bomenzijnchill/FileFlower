import SwiftUI
#if canImport(BridgeKit)
import BridgeKit
#endif

#if canImport(BridgeKit)
/// Bridge-sectie in het instellingenvenster.
///
/// Model: AccountTab — geen bindings en geen onSave, want Bridge bewaart zijn
/// eigen instellingen (machinenaam bij de engine, downloadmap en meldingen in
/// UserDefaults). Ze horen dus niet in FileFlowers Config en niet in
/// SettingsView.loadSettings/saveConfig.
///
/// De kaarten zelf komen uit BridgeKit. Dat kan omdat beide kanten hetzelfde
/// ontwerp aanhouden: 13,5 pt semibold titel, 12 pt ink3 omschrijving, cardBg
/// met 12 pt radius en een 1 pt Color.line-rand. Alleen de eerste kaart is
/// FileFlower-eigen, omdat de verkenner-knop naar een FileFlower-venster wijst
/// waar BridgeKit niets van weet.
///
/// Let op: dit tabblad tekent bewust geen PageHead — SettingsView doet dat al
/// centraal (pageEyebrow/pageTitle/pageLede).
struct BridgeTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsCard(
                title: String(localized: "settings.card.bridge_explorer", defaultValue: "Verkenner"),
                desc: String(localized: "settings.card.bridge_explorer.desc",
                             defaultValue: "Bladeren, delen en volgen gebeurt in een eigen venster — daar is meer ruimte dan in het menubalkpaneel.")
            ) {
                SettingsRow(
                    label: String(localized: "settings.bridge.open_explorer", defaultValue: "Verkenner openen"),
                    isFirst: true
                ) {
                    BrandButton(
                        title: String(localized: "common.open", defaultValue: "Openen"),
                        variant: .secondary
                    ) {
                        BridgeExplorerWindowController.show()
                    }
                }
            }

            BridgeSettingsView()
        }
    }
}
#endif
