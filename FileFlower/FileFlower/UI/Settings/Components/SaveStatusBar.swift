import SwiftUI

struct SaveStatusBar: View {
    let lastSaveTime: Date?
    let onClose: () -> Void
    var onExportConfig: (() -> Void)? = nil

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.statusOk)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 11.5))
                    .foregroundColor(.ink3)
            }

            Spacer()

            if let onExport = onExportConfig {
                BrandButton(title: String(localized: "settings.save.export_config") + "…",
                            variant: .secondary,
                            size: .regular,
                            action: onExport)
            }

            BrandButton(title: String(localized: "common.close"),
                        variant: .ghost,
                        size: .regular,
                        action: onClose)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color.line)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var statusText: String {
        let saved = String(localized: "settings.save.auto_saved")
        guard let time = lastSaveTime else { return saved }
        let interval = Date().timeIntervalSince(time)
        if interval < 5 {
            return "\(saved) · \(String(localized: "settings.save.just_now"))"
        }
        let relative = Self.formatter.localizedString(for: time, relativeTo: Date())
        return "\(saved) · \(relative)"
    }
}
