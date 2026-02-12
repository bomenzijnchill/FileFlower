import SwiftUI
import AppKit

/// License activering en status view
struct LicenseView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var licenseKey = ""
    @State private var showActivationSheet = false
    
    let onActivated: () -> Void
    let onSkip: (() -> Void)?
    let onClose: (() -> Void)?
    
    init(onActivated: @escaping () -> Void, onSkip: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.onActivated = onActivated
        self.onSkip = onSkip
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Close button (rechtsboven)
            if onClose != nil {
                HStack {
                    Spacer()
                    Button(action: { onClose?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "common.close"))
                }
                .padding(.top, -8)
                .padding(.trailing, -8)
            }
            
            // Header
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.brandBurntPeach, .brandSandyClay],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(String(localized: "license.activate_title"))
                    .font(.system(size: 24, weight: .bold))

                Text(String(localized: "license.activate_subtitle"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // License key input
            VStack(spacing: 12) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(maxWidth: 350)
                    .disabled(licenseManager.isValidating)
                
                if let error = licenseManager.licenseError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: activateLicense) {
                    HStack(spacing: 8) {
                        if licenseManager.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(licenseManager.isValidating ? String(localized: "license.validating") : String(localized: "license.activate"))
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(licenseKey.isEmpty || licenseManager.isValidating)
            }

            Divider()
                .frame(maxWidth: 300)

            // Purchase link
            VStack(spacing: 8) {
                Text(String(localized: "license.no_license"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(String(localized: "license.buy")) {
                    openPurchasePage()
                }
                .buttonStyle(.bordered)
            }
            
            // Trial info
            if licenseManager.trialDaysRemaining > 0 && onSkip != nil {
                VStack(spacing: 8) {
                    Text("of")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button(String(localized: "license.try_free \(licenseManager.trialDaysRemaining)")) {
                        onSkip?()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
                }
            }
        }
        .padding(32)
        .frame(width: 450, height: 400)
    }
    
    private func activateLicense() {
        Task {
            let result = await licenseManager.activateLicense(key: licenseKey)
            
            await MainActor.run {
                switch result {
                case .success:
                    onActivated()
                case .failure:
                    // Error wordt al getoond via licenseManager.licenseError
                    break
                }
            }
        }
    }
    
    private func openPurchasePage() {
        // Pas deze URL aan naar je Gumroad product pagina
        if let url = URL(string: "https://koendijkstra.gumroad.com/l/Fileflower") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// License status sectie voor SettingsView
struct LicenseSection: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var showActivationView = false
    @State private var showDeactivateConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("License")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                licenseBadge
            }
            
            if showActivationView {
                // Inline license activatie view (mooie overlay binnen settings)
                InlineLicenseActivationView(
                    onActivated: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showActivationView = false
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showActivationView = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            } else if licenseManager.isLicensed, let info = licenseManager.licenseInfo {
                // Licensed status
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "license.activated"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                            Text(info.email)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text(String(localized: "license.key_label"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(info.maskedKey)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(String(localized: "license.deactivate")) {
                            showDeactivateConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
                
            } else if licenseManager.isInTrial {
                // Trial status
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "license.trial"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                            Text(String(localized: "license.days_remaining \(licenseManager.trialDaysRemaining)"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(String(localized: "license.activate")) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showActivationView = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)

            } else {
                // Not licensed
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "license.not_activated"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                            Text(String(localized: "license.trial_expired"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(String(localized: "license.activate")) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showActivationView = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
        .alert(String(localized: "license.deactivate_title"), isPresented: $showDeactivateConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "license.deactivate"), role: .destructive) {
                licenseManager.deactivateLicense()
            }
        } message: {
            Text(String(localized: "license.deactivate_message"))
        }
    }
    
    @ViewBuilder
    private var licenseBadge: some View {
        if licenseManager.isLicensed {
            Text("PRO")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .cornerRadius(4)
        } else if licenseManager.isInTrial {
            Text("TRIAL")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange)
                .cornerRadius(4)
        }
    }
}

/// Inline license activatie view - voor gebruik binnen settings (voorkomt focus verlies)
struct InlineLicenseActivationView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var licenseKey = ""
    
    let onActivated: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header met close button
            HStack {
                Text(String(localized: "license.activate_title"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "common.close"))
            }
            
            // Icon
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // License key input
            VStack(spacing: 8) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .disabled(licenseManager.isValidating)
                
                if let error = licenseManager.licenseError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 10))
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button(String(localized: "license.buy_license")) {
                    if let url = URL(string: "https://koendijkstra.gumroad.com/l/Fileflower") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: activateLicense) {
                    HStack(spacing: 6) {
                        if licenseManager.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(licenseManager.isValidating ? String(localized: "license.validating") : String(localized: "license.activate"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(licenseKey.isEmpty || licenseManager.isValidating)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func activateLicense() {
        Task {
            let result = await licenseManager.activateLicense(key: licenseKey)
            
            await MainActor.run {
                switch result {
                case .success:
                    onActivated()
                case .failure:
                    // Error wordt al getoond via licenseManager.licenseError
                    break
                }
            }
        }
    }
}

/// Window controller voor license activering
class LicenseWindowController: NSObject, NSWindowDelegate {
    private static var shared: LicenseWindowController?
    private var windowController: NSWindowController?
    private var onActivatedCallback: (() -> Void)?
    private var onSkipCallback: (() -> Void)?
    
    static func show(onActivated: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        shared?.windowController?.close()
        
        let controller = LicenseWindowController()
        shared = controller
        controller.onActivatedCallback = onActivated
        controller.onSkipCallback = onSkip
        
        let licenseView = LicenseView(
            onActivated: {
                shared?.windowController?.close()
                let callback = shared?.onActivatedCallback
                shared = nil
                callback?()
            },
            onSkip: onSkip.map { _ in
                {
                    shared?.windowController?.close()
                    let callback = shared?.onSkipCallback
                    shared = nil
                    callback?()
                }
            },
            onClose: {
                shared?.windowController?.close()
                shared = nil
            }
        )
        
        let hostingController = NSHostingController(rootView: licenseView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "FileFlower Activeren"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = controller
        window.level = .floating
        
        controller.windowController = NSWindowController(window: window)
        controller.windowController?.showWindow(nil)
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    static func close() {
        shared?.windowController?.close()
        shared = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Sta toe dat het venster sluit
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        // Alleen cleanup, sluit de app NIET
        LicenseWindowController.shared = nil
    }
}

