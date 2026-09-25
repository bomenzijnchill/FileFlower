import SwiftUI

/// Koppelt een `GuideDemoID` aan zijn view.
///
/// Elke demo houdt zijn eigen fasemachine bij; `replayToken` is de trigger om
/// opnieuw af te spelen (bij binnenkomst in het hoofdstuk of via de herhaalknop).
struct GuideDemoView: View {
    let id: GuideDemoID
    let replayToken: Int

    var body: some View {
        switch id {
        case .petals:
            GuideDemoPetals(replayToken: replayToken)
        case .downloadLoop:
            GuideDemoDownloadLoop(replayToken: replayToken)
        case .pathEvidence:
            GuideDemoPathEvidence(replayToken: replayToken)
        default:
            // Nog niet gebouwd — fase 1 vult deze aan.
            Color.clear
        }
    }
}

/// Speelt de demo af bij binnenkomst en bij elke wijziging van `token`.
struct GuideDemoPlayer: ViewModifier {
    @ObservedObject var timeline: GuideDemoTimeline
    let token: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { timeline.play(reduceMotion: reduceMotion) }
            .onChange(of: token) { _, _ in timeline.play(reduceMotion: reduceMotion) }
            .onDisappear { timeline.stop() }
    }
}

extension View {
    func guidePlays(_ timeline: GuideDemoTimeline, token: Int) -> some View {
        modifier(GuideDemoPlayer(timeline: timeline, token: token))
    }
}
