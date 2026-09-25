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

    /// De voorgestelde project-root: de container boven de structurele projecthoofdmap
    /// (via klim), NOOIT blind "twee niveaus omhoog" — dat vergiftigde eerder de config
    /// bij geneste structuren zoals <project>/01_Projects/01_PremierePro/<video>/x.prproj.
    private var derivedRootPath: String {
        if let mainFolder = ProjectRootResolver.shared.climbToStructuralProjectRoot(
            fromProjectFile: project.projectPath
        ) {
            return mainFolder.deletingLastPathComponent().path
        }
        // Geen herkenbare structuur: fallback naar de directe parent-map van het project
        // (conservatiever dan grandparent — voegt hooguit een te smalle root toe, nooit
        // een map middenin een ander project).
        return URL(fileURLWithPath: project.projectPath).deletingLastPathComponent().path
    }
}
