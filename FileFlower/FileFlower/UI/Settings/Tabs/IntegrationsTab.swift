import SwiftUI

struct IntegrationsTabView: View {
    @Binding var bringPremiereToFront: Bool
    @Binding var bringResolveToFront: Bool
    @Binding var resolveAutoImport: Bool
    @Binding var customStockWebsites: [String]
    @Binding var newStockWebsite: String
    @Binding var blacklistedWebsites: [String]
    @Binding var newBlacklistedWebsite: String
    let onSave: () -> Void

    @State private var isUpdatingPlugin = false
    @State private var pluginUpdateError: String?
    @State private var pluginUpdateSuccess = false
    @State private var showStockSheet = false
    @State private var showBlacklistSheet = false
    @State private var showChromeInstructions = false

    private var pluginInfo: PluginUpdateInfo {
        UpdateManager.shared.pluginUpdateInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            // Premiere Pro
            IntegrationCard(
                logo: .premiere,
                name: "Premiere Pro",
                sub: premiereSub,
                status: pluginInfo.installedPremiereVersion != nil
                    ? String(localized: "settings.integration.connected")
                    : String(localized: "settings.not_installed"),
                statusKind: pluginInfo.installedPremiereVersion != nil ? .ok : .warn
            ) {
                SettingsRow(
                    label: String(localized: "settings.bring_premiere"),
                    help: String(localized: "settings.bring_premiere.help"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $bringPremiereToFront)
                }
                if pluginInfo.premierePluginUpdateAvailable {
                    SettingsRow(
                        label: String(localized: "settings.plugin.update_available"),
                        help: String(format: String(localized: "settings.plugin.update_to %@"),
                                     pluginInfo.bundledPremiereVersion ?? "")
                    ) {
                        if isUpdatingPlugin {
                            ProgressView().controlSize(.small)
                        } else {
                            BrandButton(title: String(localized: "settings.plugin.update_now"),
                                        variant: .primary, size: .regular, action: updatePlugin)
                        }
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.plugin.reinstall"),
                    help: String(localized: "settings.plugin.reinstall.help")
                ) {
                    BrandButton(title: String(localized: "settings.plugin.reinstall.button"),
                                variant: .secondary, size: .regular) {
                        _ = SetupManager.shared.installPremierePlugin()
                    }
                }
            }

            // DaVinci Resolve
            IntegrationCard(
                logo: .resolve,
                name: "DaVinci Resolve",
                sub: resolveSub,
                status: ResolveScriptManager.shared.isRunning
                    ? String(localized: "settings.integration.bridge_running")
                    : String(localized: "settings.resolve_bridge.stopped"),
                statusKind: ResolveScriptManager.shared.isRunning ? .ok : .warn
            ) {
                SettingsRow(
                    label: String(localized: "settings.bring_resolve"),
                    isFirst: true
                ) {
                    BrandToggle(isOn: $bringResolveToFront)
                }
                SettingsRow(
                    label: String(localized: "settings.resolve_auto_import"),
                    help: String(localized: "settings.resolve_auto_import.help")
                ) {
                    BrandToggle(isOn: $resolveAutoImport)
                }
            }

            // Browser extension
            IntegrationCard(
                logo: .browser,
                name: String(localized: "settings.integration.browser_ext"),
                sub: chromeSub,
                status: pluginInfo.chromeExtensionUpdateAvailable
                    ? String(localized: "settings.update_available")
                    : (pluginInfo.installedChromeVersion != nil
                        ? String(localized: "settings.integration.connected")
                        : String(localized: "settings.not_installed_manual")),
                statusKind: pluginInfo.chromeExtensionUpdateAvailable ? .warn : (pluginInfo.installedChromeVersion != nil ? .ok : .warn)
            ) {
                SettingsRow(
                    label: String(localized: "settings.integration.view_install_instructions"),
                    help: String(localized: "settings.integration.view_install_instructions.help"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.integration.open_instructions"),
                                icon: "arrow.up.right.square",
                                variant: .secondary, size: .regular) {
                        showChromeInstructions = true
                    }
                }
            }

            // Stock sources
            SettingsCard(
                title: String(localized: "settings.card.stock_sources"),
                desc: String(localized: "settings.card.stock_sources.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.stock_sources.manage"),
                    help: String(localized: "settings.stock_sources.manage.help"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.stock_sources.manage.button") + " →",
                                variant: .secondary, size: .regular) {
                        showStockSheet = true
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.blacklist_websites"),
                    help: String(localized: "settings.blacklist_description")
                ) {
                    BrandButton(title: String(localized: "settings.blacklist.manage") + " →",
                                variant: .secondary, size: .regular) {
                        showBlacklistSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showStockSheet) {
            StockWebsitesSheet(
                customStockWebsites: $customStockWebsites,
                newStockWebsite: $newStockWebsite,
                onSave: onSave,
                onClose: { showStockSheet = false }
            )
        }
        .sheet(isPresented: $showBlacklistSheet) {
            BlacklistWebsitesSheet(
                blacklistedWebsites: $blacklistedWebsites,
                newBlacklistedWebsite: $newBlacklistedWebsite,
                onSave: onSave,
                onClose: { showBlacklistSheet = false }
            )
        }
        .sheet(isPresented: $showChromeInstructions) {
            ChromeExtensionInstructionsSheet(onClose: { showChromeInstructions = false })
        }
    }

    private var premiereSub: String {
        if let v = pluginInfo.installedPremiereVersion {
            return "Plugin v\(v) · " + String(localized: "settings.integration.panel_active")
        }
        return String(localized: "settings.not_installed")
    }

    private var resolveSub: String {
        let v = "Bridge v0.9.2 · " + String(localized: "settings.integration.port") + " :8765"
        return v
    }

    private var chromeSub: String {
        if let v = pluginInfo.installedChromeVersion {
            return "v\(v) · Chrome · Edge · Brave"
        }
        return "Chrome · Edge · Brave"
    }

    private func updatePlugin() {
        isUpdatingPlugin = true
        pluginUpdateError = nil
        pluginUpdateSuccess = false

        DispatchQueue.global(qos: .userInitiated).async {
            let result = UpdateManager.shared.updatePremierePlugin()
            DispatchQueue.main.async {
                isUpdatingPlugin = false
                switch result {
                case .success: pluginUpdateSuccess = true
                case .failure(let error): pluginUpdateError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Stock & blacklist sheets

private struct StockWebsitesSheet: View {
    @Binding var customStockWebsites: [String]
    @Binding var newStockWebsite: String
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "settings.stock_websites"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.ink3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(customStockWebsites, id: \.self) { website in
                        HStack {
                            Text(website)
                                .font(.brandMono(size: 12))
                                .foregroundColor(.ink2)
                            Spacer()
                            Button(action: {
                                customStockWebsites.removeAll { $0 == website }
                                onSave()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.ink3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.line, lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                }
                .padding()
            }

            Divider()

            HStack(spacing: 6) {
                TextField(String(localized: "settings.example_website"), text: $newStockWebsite)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                BrandButton(title: String(localized: "common.add"), variant: .primary, size: .regular) {
                    if !newStockWebsite.isEmpty && !customStockWebsites.contains(newStockWebsite) {
                        customStockWebsites.append(newStockWebsite)
                        newStockWebsite = ""
                        onSave()
                    }
                }
                .disabled(newStockWebsite.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
        .background(Color.paper0)
    }
}

private struct BlacklistWebsitesSheet: View {
    @Binding var blacklistedWebsites: [String]
    @Binding var newBlacklistedWebsite: String
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "settings.blacklist_websites"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.ink3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(blacklistedWebsites, id: \.self) { website in
                        HStack {
                            Text(website)
                                .font(.brandMono(size: 12))
                                .foregroundColor(.ink2)
                            Spacer()
                            Button(action: {
                                blacklistedWebsites.removeAll { $0 == website }
                                onSave()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.ink3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.line, lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                }
                .padding()
            }

            Divider()

            HStack(spacing: 6) {
                TextField(String(localized: "settings.example_website"), text: $newBlacklistedWebsite)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                BrandButton(title: String(localized: "common.add"), variant: .primary, size: .regular) {
                    if !newBlacklistedWebsite.isEmpty && !blacklistedWebsites.contains(newBlacklistedWebsite) {
                        blacklistedWebsites.append(newBlacklistedWebsite)
                        newBlacklistedWebsite = ""
                        onSave()
                    }
                }
                .disabled(newBlacklistedWebsite.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
        .background(Color.paper0)
    }
}

// MARK: - Chrome extension instructions sheet

private struct ChromeExtensionInstructionsSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "settings.chrome.instructions_title"))
                    .font(.brandSerifItalic(size: 22))
                    .foregroundColor(.ink)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.ink3)
                }
                .buttonStyle(.plain)
            }

            Text(String(localized: "settings.chrome.instructions_intro"))
                .font(.system(size: 12.5))
                .foregroundColor(.ink2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(number: 1, text: String(localized: "settings.chrome.step1"))
                stepRow(number: 2, text: String(localized: "settings.chrome.step2"))
                stepRow(number: 3, text: String(localized: "settings.chrome.step3"))
                stepRow(number: 4, text: String(localized: "settings.chrome.step4"))
            }

            Spacer()

            HStack(spacing: 8) {
                BrandButton(title: String(localized: "settings.chrome.copy_to_documents"),
                            icon: "folder",
                            variant: .secondary, size: .regular) {
                    SetupManager.shared.openChromeExtensionFolder()
                }
                BrandButton(title: String(localized: "settings.chrome.open_extensions_page"),
                            icon: "arrow.up.right.square",
                            variant: .primary, size: .regular) {
                    if let url = URL(string: "chrome://extensions") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                BrandButton(title: String(localized: "common.close"),
                            variant: .ghost, size: .regular,
                            action: onClose)
            }
        }
        .padding(24)
        .frame(width: 540, height: 460)
        .background(Color.paper0)
    }

    @ViewBuilder
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.brandMono(size: 12, weight: .semibold))
                .foregroundColor(.peach3)
                .frame(width: 22, height: 22)
                .background(Color.brandBurntPeach.opacity(0.12))
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
