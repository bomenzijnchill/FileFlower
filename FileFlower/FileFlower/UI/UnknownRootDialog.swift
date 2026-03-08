import SwiftUI

struct UnknownRootDialog: View {
    let project: ProjectInfo
    let onResolve: (UnknownRootResolution) -> Void
    @State private var addRoot = true

    enum UnknownRootResolution {
        case proceedAndAddRoot(String)
        case proceedWithout
        case cancel
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "unknown_root.title"))
                .font(.headline)

            Text(String(localized: "unknown_root.message"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                Text(project.projectPath)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 60)

            Toggle(isOn: $addRoot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "unknown_root.add_root"))
                        .font(.system(size: 13))
                    Text(derivedRootPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            HStack {
                Button(String(localized: "common.cancel")) {
                    onResolve(.cancel)
                }

                Spacer()

                Button(String(localized: "unknown_root.proceed")) {
                    if addRoot {
                        onResolve(.proceedAndAddRoot(derivedRootPath))
                    } else {
                        onResolve(.proceedWithout)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// De parent directory van de parent van het project bestand (grandparent van .prproj)
    private var derivedRootPath: String {
        let url = URL(fileURLWithPath: project.projectPath)
        return url.deletingLastPathComponent().deletingLastPathComponent().path
    }
}
