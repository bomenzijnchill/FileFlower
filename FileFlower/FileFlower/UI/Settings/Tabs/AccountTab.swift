import SwiftUI

struct AccountTabView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @StateObject private var updateManager = UpdateManager.shared

    @State private var lastUpdateCheck: Date? = nil

    private var heroPrimary: (title: String, action: () -> Void)? {
        if licenseManager.isLicensed {
            return (title: String(localized: "license.open_portal") + " →", action: openCustomerPortal)
        }
        return (title: String(localized: "license.activate"), action: openLicenseActivation)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Account hero
            AccountHero(
                role: heroRole,
                name: heroName,
                meta: heroMeta,
                primaryAction: heroPrimary
            )

            // Updates
            SettingsCard(
                title: String(localized: "settings.card.updates"),
                desc: updatesDesc
            ) {
                SettingsRow(
                    label: String(localized: "settings.updates.check"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.updates.check_now"),
                                variant: .primary, size: .regular) {
                        updateManager.checkForUpdates()
                        lastUpdateCheck = Date()
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.updates.auto_check"),
                    help: String(localized: "settings.updates.auto_check.help")
                ) {
                    BrandToggle(isOn: Binding(
                        get: { updateManager.automaticUpdatesEnabled },
                        set: { updateManager.automaticUpdatesEnabled = $0 }
                    ))
                }
            }

            // Feedback
            SettingsCard(
                title: String(localized: "settings.card.feedback"),
                desc: String(localized: "settings.card.feedback.desc")
            ) {
                SettingsRow(
                    label: String(localized: "settings.feedback.open_form"),
                    isFirst: true
                ) {
                    BrandButton(title: String(localized: "settings.feedback.open_form.button"),
                                variant: .secondary, size: .regular) {
                        FeedbackWindowController.show()
                    }
                }
                SettingsRow(
                    label: String(localized: "settings.feedback.show_log"),
                    help: String(localized: "settings.feedback.show_log.help")
                ) {
                    BrandButton(title: String(localized: "settings.feedback.reveal_in_finder"),
                                variant: .secondary, size: .regular) {
                        revealLogsInFinder()
                    }
                }
            }
        }
    }

    // MARK: - Hero data

    private var heroRole: String {
        if licenseManager.isLicensed { return String(localized: "license.pro_license") }
        if licenseManager.isInTrial { return String(localized: "license.trial") }
        return String(localized: "license.no_license")
    }

    private var heroName: String {
        if licenseManager.isLicensed, let info = licenseManager.licenseInfo {
            return info.email
        }
        if licenseManager.isInTrial {
            return String(localized: "license.trial_active")
        }
        return String(localized: "license.activate_subtitle")
    }

    private var heroMeta: String {
        if licenseManager.isLicensed, let info = licenseManager.licenseInfo {
            return String(localized: "license.key_label") + " " + info.maskedKey
        }
        if licenseManager.isInTrial {
            return String(format: String(localized: "license.days_remaining %lld"),
                          licenseManager.trialDaysRemaining)
        }
        return ""
    }

    // MARK: - Helpers

    private var updatesDesc: String {
        let version = "v\(updateManager.currentVersion) · build \(updateManager.buildNumber)"
        if let last = lastUpdateCheck {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "\(version) · \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return version
    }

    private func openCustomerPortal() {
        if let url = URL(string: "https://gumroad.com/library") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openLicenseActivation() {
        LicenseWindowController.show(onActivated: {}, onSkip: nil)
    }

    private func revealLogsInFinder() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("FileFlower")
        if let url = url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - Feedback window controller (wraps existing FeedbackSectionView in own window)

class FeedbackWindowController: NSObject, NSWindowDelegate {
    private static var windowController: NSWindowController?
    private static var delegate: FeedbackWindowController?

    static func show() {
        if let existing = windowController, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let delegateInstance = FeedbackWindowController()
        delegate = delegateInstance

        let view = FeedbackSectionView()
            .frame(width: 460, height: 520)
            .background(Color.paper0)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "settings.feedback")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = delegateInstance

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        FeedbackWindowController.windowController = nil
        FeedbackWindowController.delegate = nil
    }
}

// MARK: - Feedback section (extracted from old SettingsView)

enum FeedbackType: String, CaseIterable {
    case featureRequest
    case bugReport
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case success
    case error(String)
}

struct FeedbackSectionView: View {
    @State private var selectedFeedbackType: FeedbackType = .featureRequest
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var sendState: FeedbackSendState = .idle

    private static let proxyBaseURL = "https://fileflower-proxy.fileflower.workers.dev"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.feedback"))
                .font(.system(size: 14, weight: .semibold))

            Picker("", selection: $selectedFeedbackType) {
                Text(String(localized: "settings.feedback.feature_request")).tag(FeedbackType.featureRequest)
                Text(String(localized: "settings.feedback.report_bug")).tag(FeedbackType.bugReport)
            }
            .pickerStyle(.segmented)
            .tint(.brandBurntPeach)
            .disabled(sendState == .sending)

            switch sendState {
            case .idle, .error:
                feedbackForm
            case .sending:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            case .success:
                successView
            }
        }
        .padding(20)
    }

    private var feedbackForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "settings.feedback.name_placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)
            TextField(String(localized: "settings.feedback.email_placeholder"), text: $email)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $message)
                .font(.system(size: 12))
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.line2, lineWidth: 0.5))

            if case .error(let msg) = sendState {
                Text(msg).font(.system(size: 11)).foregroundColor(.statusBad)
            }

            HStack {
                Spacer()
                BrandButton(title: String(localized: "settings.feedback.send"),
                            icon: "paperplane.fill",
                            variant: .primary, size: .regular,
                            action: sendFeedback)
                    .disabled(name.isEmpty || email.isEmpty || message.isEmpty)
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.statusOk)
            Text(String(localized: "settings.feedback.success"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.statusOk)
            BrandButton(title: String(localized: "settings.feedback.send_another"),
                        variant: .secondary, size: .regular) {
                sendState = .idle
                name = ""; email = ""; message = ""
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func sendFeedback() {
        sendState = .sending
        Task {
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let deviceId = AppState.shared.config.anonymousId

            guard let url = URL(string: "\(Self.proxyBaseURL)/api/feedback") else {
                await MainActor.run { sendState = .error(String(localized: "settings.feedback.error.send_failed")) }
                return
            }

            let body: [String: String] = [
                "type": selectedFeedbackType.rawValue,
                "name": name, "email": email, "message": message,
                "appVersion": appVersion, "osVersion": osVersion
            ]
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
            req.timeoutInterval = 15

            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    await MainActor.run { sendState = .error(String(localized: "settings.feedback.error.send_failed")) }
                    return
                }
                if http.statusCode == 200 {
                    await MainActor.run { sendState = .success }
                } else if http.statusCode == 429 {
                    await MainActor.run { sendState = .error(String(localized: "settings.feedback.error.rate_limit")) }
                } else {
                    await MainActor.run { sendState = .error(String(localized: "settings.feedback.error.send_failed")) }
                }
            } catch {
                await MainActor.run { sendState = .error(String(localized: "settings.feedback.error.network")) }
            }
        }
    }
}
