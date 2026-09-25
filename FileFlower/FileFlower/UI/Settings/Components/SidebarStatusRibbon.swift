import SwiftUI

/// Bottom of sidebar: live status rows.
/// Shows Resolve bridge + Premiere plugin + Chrome extension.
struct SidebarStatusRibbon: View {
    @StateObject private var updateManager = UpdateManager.shared

    var body: some View {
        VStack(spacing: 6) {
            statusRow(
                key: "Resolve bridge",
                value: ResolveScriptManager.shared.isRunning ? ":8765" : String(localized: "settings.health.status.stopped"),
                kind: ResolveScriptManager.shared.isRunning ? .ok : .warn
            )

            statusRow(
                key: "Premiere plugin",
                value: updateManager.pluginUpdateInfo.installedPremiereVersion.map { "v\($0)" }
                    ?? String(localized: "settings.health.status.not_installed"),
                kind: updateManager.pluginUpdateInfo.installedPremiereVersion != nil ? .ok : .warn
            )

            statusRow(
                key: "Browser ext",
                value: updateManager.pluginUpdateInfo.installedChromeVersion.map { "v\($0)" }
                    ?? String(localized: "settings.health.status.not_installed"),
                kind: updateManager.pluginUpdateInfo.installedChromeVersion != nil ? .ok : .warn
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            Rectangle()
                .fill(Color.line)
                .frame(height: 1),
            alignment: .top
        )
    }

    private enum StatusKind { case ok, warn, bad }

    @ViewBuilder
    private func statusRow(key: String, value: String, kind: StatusKind) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11))
                .foregroundColor(.ink3)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor(kind))
                    .frame(width: 7, height: 7)
                Text(value)
                    .font(.system(size: 11))
                    .foregroundColor(.ink2)
            }
        }
    }

    private func dotColor(_ kind: StatusKind) -> Color {
        switch kind {
        case .ok: return .statusOk
        case .warn: return .statusWarn
        case .bad: return .statusBad
        }
    }
}
