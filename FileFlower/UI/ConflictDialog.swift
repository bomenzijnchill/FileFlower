import SwiftUI

struct ConflictDialog: View {
    let item: DownloadItem
    let onResolve: (ConflictResolution) -> Void
    @State private var resolution: ConflictResolution = .skip
    
    enum ConflictResolution {
        case overwrite
        case version
        case skip
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "conflict.title"))
                .font(.headline)

            Text(String(localized: "conflict.file_exists"))
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(URL(fileURLWithPath: item.targetPath ?? "").lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 100)
            
            Picker(String(localized: "conflict.action"), selection: $resolution) {
                Text(String(localized: "conflict.overwrite")).tag(ConflictResolution.overwrite)
                Text(String(localized: "conflict.version")).tag(ConflictResolution.version)
                Text(String(localized: "conflict.skip")).tag(ConflictResolution.skip)
            }
            .pickerStyle(.radioGroup)
            
            Spacer()
            
            HStack {
                Button(String(localized: "common.cancel")) {
                    onResolve(.skip)
                }

                Spacer()

                Button(String(localized: "common.confirm")) {
                    onResolve(resolution)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

