import SwiftUI
import AppKit

// MARK: - Parameter value form

/// SwiftUI form dat bij deploy om parameter-waarden vraagt.
/// `cannotBeEmpty` violations worden live getoond en blokkeren submit.
struct ParameterValueForm: View {
    let templateName: String
    let parameters: [TemplateParameter]
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var values: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "folder_structure.deploy.fill_params"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(templateName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 10) {
                ForEach(parameters) { param in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(param.title)
                                .font(.system(size: 12, weight: .medium))
                            if param.cannotBeEmpty {
                                Text("*").foregroundColor(.red)
                            }
                            Spacer()
                        }

                        TextField(param.defaultValue, text: Binding(
                            get: { values[param.id] ?? "" },
                            set: { values[param.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        if violationMessage(for: param) != nil {
                            Text(String(localized: "folder_structure.deploy.missing_param"))
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                }

                if parameters.isEmpty {
                    Text(String(localized: "folder_structure.deploy.no_params"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button(String(localized: "common.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(String(localized: "common.create")) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hasAnyViolation)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear { prefillDefaults() }
    }

    // MARK: - Logic

    private var hasAnyViolation: Bool {
        parameters.contains(where: { violationMessage(for: $0) != nil })
    }

    private func violationMessage(for param: TemplateParameter) -> String? {
        guard param.cannotBeEmpty else { return nil }
        let value = values[param.id]?.trimmingCharacters(in: .whitespaces) ?? ""
        if value.isEmpty && param.defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "folder_structure.deploy.missing_param")
        }
        return nil
    }

    private func prefillDefaults() {
        for param in parameters where values[param.id] == nil {
            values[param.id] = ""
        }
    }

    private func submit() {
        // Bouw dict met title → value (of default als leeg)
        var result: [String: String] = [:]
        for param in parameters {
            let raw = values[param.id]?.trimmingCharacters(in: .whitespaces) ?? ""
            let final = raw.isEmpty ? param.defaultValue : raw
            result[param.title] = final
        }
        onSubmit(result)
    }
}

// MARK: - Window controller voor gebruik vanuit FinderSync notification-handler

final class ParameterValueWindowController: NSWindowController {
    static var shared: ParameterValueWindowController?

    private var onResult: (([String: String]?) -> Void)?

    init(templateName: String,
         parameters: [TemplateParameter],
         onResult: @escaping ([String: String]?) -> Void) {
        self.onResult = onResult

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "folder_structure.deploy.window_title")
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let form = ParameterValueForm(
            templateName: templateName,
            parameters: parameters,
            onSubmit: { values in
                onResult(values)
                ParameterValueWindowController.shared?.close()
            },
            onCancel: {
                onResult(nil)
                ParameterValueWindowController.shared?.close()
            }
        )
        window.contentView = NSHostingView(rootView: form)

        super.init(window: window)
        ParameterValueWindowController.shared = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        window?.close()
        ParameterValueWindowController.shared = nil
    }
}

// MARK: - Helper voor entry-points (FileSafe, FinderSync, JobServer)

enum TemplateDeployFlow {
    /// Bepaalt de actieve template uit config. Nil als de user geen default heeft.
    static func activeTemplate(for config: Config) -> FolderStructureTemplate? {
        guard let id = config.defaultTemplateId else { return nil }
        return config.folderTemplates.first(where: { $0.id == id })
    }

    /// Bepaalt of een parameter-prompt nodig is. Wanneer alle parameters een non-empty default hebben
    /// en niks is cannotBeEmpty zonder default, kan de deploy silent verlopen.
    static func needsPrompt(for template: FolderStructureTemplate) -> Bool {
        for param in template.parameters {
            if param.cannotBeEmpty && param.defaultValue.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
        }
        // Ook prompten als er überhaupt user-facing parameters zijn
        return !template.parameters.isEmpty
    }

    /// Verzamel default values als de prompt geskipt mag worden.
    static func defaultValues(for template: FolderStructureTemplate) -> [String: String] {
        var result: [String: String] = [:]
        for param in template.parameters {
            result[param.title] = param.defaultValue
        }
        return result
    }
}
