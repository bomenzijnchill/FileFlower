import SwiftUI
import AppKit

/// Toont een korte bloemblaadjes-animatie in een zwevend venster bij het menu bar icoon.
/// Gebruik `PetalAnimationWindow.play()` om de animatie af te spelen.
enum PetalAnimationWindow {
    private static var window: NSWindow?

    /// Speel de bloemblaadjes-animatie af bij het menu bar icoon.
    @MainActor
    static func play() {
        // Voorkom overlappende animaties
        window?.close()
        window = nil

        guard let iconFrame = StatusBarController.shared.statusItemFrame else { return }

        let size = NSSize(width: 160, height: 200)

        // Centreer horizontaal op het icoon, net eronder
        let origin = NSPoint(
            x: iconFrame.midX - size.width / 2,
            y: iconFrame.minY - size.height + 20
        )

        let animationWindow = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        animationWindow.isOpaque = false
        animationWindow.backgroundColor = .clear
        animationWindow.hasShadow = false
        animationWindow.ignoresMouseEvents = true
        animationWindow.level = .statusBar
        animationWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationWindow.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView:
            PetalAnimationView()
                .frame(width: size.width, height: size.height)
        )
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        animationWindow.contentView = hostingView

        // Toon zonder focus te stelen
        animationWindow.orderFrontRegardless()
        window = animationWindow

        // Sluit automatisch na de animatie (1.5s + 0.3s delay + 0.2s buffer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            window?.close()
            window = nil
        }
    }
}
