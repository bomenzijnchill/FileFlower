import SwiftUI

/// Hoofdstuk 4 — hoe FileFlower de juiste map kiest: drie signalen worden gewogen,
/// en cachemappen worden hard geblokkeerd.
struct GuideDemoPathEvidence: View {
    let replayToken: Int

    // 0 leeg · 1-3 bewijslagen · 4 uitkomst · 5 geblokkeerde map
    @StateObject private var timeline = GuideDemoTimeline([0.35, 0.35, 0.35, 0.55, 0.65, 0])

    private var phase: Int { timeline.phase }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            EvidenceRow(
                label: String(localized: "guide.demo.path.signal_folders"),
                fraction: 0.90, score: "0.90", color: .brandSkyBlue,
                phase: phase, at: 1
            )
            EvidenceRow(
                label: String(localized: "guide.demo.path.signal_neighbours"),
                fraction: 0.70, score: "0.70", color: .brandSandyClay,
                phase: phase, at: 2
            )
            EvidenceRow(
                label: String(localized: "guide.demo.path.signal_keywords"),
                fraction: 0.40, score: "0.40", color: .petalLavender,
                phase: phase, at: 3
            )

            resultRow
            blockedRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .guidePlays(timeline, token: replayToken)
    }

    private var resultRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
            Text("PROJECT_A/03_Audio/01_Music/Uplifting")
                .font(.brandMono(size: 10.5, weight: .semibold))
        }
        .foregroundColor(.destChipInk)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.destChipBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .guideLand(phase, at: 4)
        .padding(.top, 4)
    }

    private var blockedRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "nosign")
                .font(.system(size: 10, weight: .semibold))
            Text("Adobe Premiere Pro Audio Previews/")
                .font(.brandMono(size: 10))
                .strikethrough(true, color: .fsBannerBadInk)
            Text(String(localized: "guide.demo.path.blocked"))
                .font(.brandMono(size: 10))
                .opacity(0.75)
        }
        .foregroundColor(.fsBannerBadInk)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fsBannerBad)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(phase >= 5 ? 1 : 0)
        .animation(GuideMotion.appear, value: phase >= 5)
        .keyframeAnimator(initialValue: 0.0, trigger: phase >= 5) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-3, duration: 0.12)
                CubicKeyframe(3, duration: 0.12)
                CubicKeyframe(-2, duration: 0.12)
                CubicKeyframe(0, duration: 0.14)
            }
        }
    }
}

/// Eén gewogen signaal: label, gevulde balk, score.
private struct EvidenceRow: View {
    let label: String
    let fraction: CGFloat
    let score: String
    let color: Color
    let phase: Int
    let at: Int

    private var shown: Bool { phase >= at }

    var body: some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.brandMono(size: 10))
                .foregroundColor(.ink2)
                .frame(width: 108, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.line2)
                    Capsule()
                        .fill(color)
                        .frame(width: shown ? geo.size.width * fraction : 0)
                        .animation(GuideMotion.fill.delay(0.15), value: shown)
                }
            }
            .frame(height: 6)

            Text(score)
                .font(.brandMono(size: 10))
                .foregroundColor(.ink3)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .guideAppear(phase, at: at)
    }
}
