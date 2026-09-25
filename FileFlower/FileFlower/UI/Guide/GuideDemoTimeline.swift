import SwiftUI
import Combine

/// Fasemachine achter elke gids-demo.
///
/// Een demo is een reeks fases; elementen verschijnen zodra `phase` hun drempel haalt.
/// De demo speelt één keer af en blijft daarna op het eindbeeld staan — geen eeuwige
/// loop naast leestekst.
///
/// Bewust met `Timer` in plaats van `Task`: deze toolchain (Swift 6.2.4) crasht op
/// `Task.detached` met self-capture in SwiftUI-context, zie het projectgeheugen
/// over de ClosureLifetimeFixup-crash. Een timer op de main runloop omzeilt dat.
final class GuideDemoTimeline: ObservableObject {
    /// Huidige fase. `-1` = nog niets getoond.
    @Published private(set) var phase: Int = -1

    /// Duur per fase, in seconden. `durations.count` = aantal fases.
    private let durations: [TimeInterval]
    private var timer: Timer?

    init(_ durations: [TimeInterval]) {
        self.durations = durations
    }

    /// Aantal fases; de demo is klaar als `phase` hier op staat.
    var lastPhase: Int { durations.count - 1 }

    var isFinished: Bool { phase >= lastPhase }

    /// Speelt de demo vanaf het begin af.
    /// Bij "Verminder beweging" springt hij direct naar het eindbeeld.
    func play(reduceMotion: Bool) {
        stop()
        guard !durations.isEmpty else { return }

        if reduceMotion {
            phase = lastPhase
            return
        }

        phase = 0
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Springt naar het eindbeeld zonder de tussenfases af te wachten.
    func skipToEnd() {
        stop()
        phase = lastPhase
    }

    private func scheduleNext() {
        guard phase < lastPhase else { return }
        let delay = durations[phase]

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.phase += 1
            self.scheduleNext()
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - Bewegingstaal

/// De vijf gebaren van de gids. Overal hetzelfde, zodat er geen tweede
/// bewegingstaal naast die van de app ontstaat.
enum GuideMotion {
    /// Verschijnen: opacity + 7pt omhoog.
    static let appear = Animation.smooth(duration: 0.34)
    /// Landen: scale 0.8 → 1, met veerkracht.
    static let land = Animation.bouncy(duration: 0.4, extraBounce: 0.3)
    /// Vullen: breedte 0 → n.
    static let fill = Animation.easeInOut(duration: 0.7)
    /// Wegwaaien: drift + fade + krimpen, zoals de bloemblaadjes.
    static let drift = Animation.easeOut(duration: 1.5)
    /// Afgewezen: korte horizontale schud.
    static let reject = Animation.easeInOut(duration: 0.5)
}

/// Laat een element verschijnen zodra de demo fase `at` bereikt heeft.
struct GuideAppear: ViewModifier {
    let phase: Int
    let at: Int
    var animation: Animation = GuideMotion.appear
    var offset: CGFloat = 7

    private var shown: Bool { phase >= at }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : offset)
            .animation(animation, value: shown)
    }
}

/// Laat een element "landen": schaalt op met veerkracht.
struct GuideLand: ViewModifier {
    let phase: Int
    let at: Int

    private var shown: Bool { phase >= at }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.8)
            .animation(GuideMotion.land, value: shown)
    }
}

extension View {
    /// Verschijnt vanaf fase `at`.
    func guideAppear(_ phase: Int, at: Int, offset: CGFloat = 7) -> some View {
        modifier(GuideAppear(phase: phase, at: at, offset: offset))
    }

    /// Landt vanaf fase `at`.
    func guideLand(_ phase: Int, at: Int) -> some View {
        modifier(GuideLand(phase: phase, at: at))
    }
}
