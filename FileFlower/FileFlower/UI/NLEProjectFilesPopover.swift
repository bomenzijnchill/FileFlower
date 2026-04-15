import SwiftUI

/// Herbruikbare popover die een lijst NLE-projectbestanden (.prproj / .drp)
/// toont voor een gegeven folder — de gebruiker kiest één bestand.
///
/// Gebruikt in zowel `ProjectSelectorView` (voor "Open project") als
/// `FileSafeReportView` (voor "Import footage na kopie").
struct NLEProjectFilesPopover: View {
    let files: [URL]
    let emptyMessage: String
    let onPick: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if files.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                ForEach(files, id: \.self) { url in
                    Button {
                        onPick(url)
                    } label: {
                        HStack(spacing: 6) {
                            if let nle = NLEType.from(projectPath: url.path) {
                                Image(systemName: nle.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Text(url.lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 220, maxWidth: 360)
    }
}
