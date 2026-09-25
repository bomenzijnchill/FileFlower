import SwiftUI

/// Hoofdstuk 1 — de landingsanimatie van de app, als openingsbeeld.
struct GuideDemoPetals: View {
    let replayToken: Int

    // 0 = leeg · 1 = merkteken landt · 2 = blaadjes waaien op + onderschrift
    @StateObject private var timeline = GuideDemoTimeline([0.55, 1.1, 0])

    private var phase: Int { timeline.phase }

    var body: some View {
        ZStack {
            GuidePetalBurst(active: phase >= 2, count: 12, spread: 60)

            Image("FileFlowerLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54)
                .guideLand(phase, at: 1)

            VStack {
                Spacer()
                Text(String(localized: "guide.demo.petals.caption"))
                    .font(.brandMono(size: 10))
                    .foregroundColor(.ink3)
                    .guideAppear(phase, at: 2)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .guidePlays(timeline, token: replayToken)
    }
}
