import SwiftUI

/// Popover die de verwerkingsgeschiedenis van vandaag toont
struct HistoryView: View {
    let records: [HistoryItem]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)

                Text(String(localized: "history.title"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text(String(localized: "history.today_count \(records.count)"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)

            Divider()

            // Content
            if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(String(localized: "history.empty"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records) { record in
                            HistoryItemRow(record: record)
                        }
                    }
                }
            }
        }
    }
}

/// Rij voor een enkel history item
struct HistoryItemRow: View {
    let record: HistoryItem
    @State private var isHovered = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: iconForType(record.assetType))
                .font(.system(size: 16))
                .foregroundColor(.accentColor.opacity(0.7))
                .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if record.isFolder {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Text(record.filename)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(record.assetType.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)

                    if let project = record.targetProject {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(project)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if record.isFolder && record.fileCount > 1 {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(String(localized: "history.file_count \(record.fileCount)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Status + tijd
            VStack(alignment: .trailing, spacing: 3) {
                HistoryStatusBadge(status: record.status)

                Text(timeString)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func iconForType(_ type: AssetType) -> String {
        switch type {
        case .music: return "music.note"
        case .sfx: return "waveform"
        case .vo: return "mic"
        case .motionGraphic: return "video"
        case .graphic: return "photo"
        case .stockFootage: return "film"
        case .unknown: return "questionmark"
        }
    }
}

/// Compacte status badge voor history items
struct HistoryStatusBadge: View {
    let status: ItemStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(status.color.opacity(0.15))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
}
