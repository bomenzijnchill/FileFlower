import Foundation
import AppKit

/// Protocol voor NLE applicatie detectie
protocol NLECheckerProtocol {
    var nleType: NLEType { get }
    func isRunning() -> Bool
    func bringToFront()
}

/// Centrale service voor het detecteren van NLE applicaties
class NLEChecker {
    static let shared = NLEChecker()

    private let checkers: [NLECheckerProtocol] = [
        PremiereNLEChecker(),
        ResolveNLEChecker()
    ]

    private init() {}

    /// Check of er minstens één ondersteunde NLE draait
    func isAnyNLERunning() -> Bool {
        checkers.contains { $0.isRunning() }
    }

    /// Alle momenteel draaiende NLE's
    func runningNLEs() -> [NLEType] {
        checkers.filter { $0.isRunning() }.map { $0.nleType }
    }

    /// Check of een specifieke NLE draait
    func isRunning(_ type: NLEType) -> Bool {
        checkers.first { $0.nleType == type }?.isRunning() ?? false
    }

    /// Breng een specifieke NLE naar de voorgrond
    func bringToFront(_ type: NLEType) {
        checkers.first { $0.nleType == type }?.bringToFront()
    }
}

// MARK: - Premiere Pro Checker

class PremiereNLEChecker: NLECheckerProtocol {
    let nleType: NLEType = .premiere

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier?.lowercased().hasPrefix("com.adobe.premierepro") == true ||
            app.localizedName?.contains("Premiere Pro") == true
        }
    }

    func bringToFront() {
        if let app = NSWorkspace.shared.runningApplications.first(where: { app in
            app.bundleIdentifier?.lowercased().hasPrefix("com.adobe.premierepro") == true ||
            app.localizedName?.contains("Premiere Pro") == true
        }) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
}

// MARK: - DaVinci Resolve Checker

class ResolveNLEChecker: NLECheckerProtocol {
    let nleType: NLEType = .resolve

    private let bundleIDs = [
        "com.blackmagic-design.DaVinciResolve",
        "com.blackmagic-design.DaVinciResolveStudio"
    ]

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return self.bundleIDs.contains(bundleID) ||
                   app.localizedName?.contains("DaVinci Resolve") == true
        }
    }

    func bringToFront() {
        if let app = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return self.bundleIDs.contains(bundleID) ||
                   app.localizedName?.contains("DaVinci Resolve") == true
        }) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
}
