import SwiftUI

/// Hoofdstuk 3 — de kernlus: een download komt binnen, wordt herkend, krijgt een
/// bestemming en landt in de juiste map.
struct GuideDemoDownloadLoop: View {
    let replayToken: Int

    // 0 bron · 1 bestand valt binnen · 2 classificeren · 3 labels · 4 pad
    // 5 het bestand vliegt naar de map · 6 de vrijgekomen ruimte valt dicht
    @StateObject private var timeline = GuideDemoTimeline([0.5, 0.7, 1.1, 0.9, 1.0, 0.75, 0])

    private var phase: Int { timeline.phase }
    /// Het bestand is onderweg naar de map.
    private var landed: Bool { phase >= 5 }
    /// Het chip is aangekomen; zijn plek in de kolom mag dichtvallen.
    private var cleared: Bool { phase >= 6 }

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
            Divider()
            treeColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .guidePlays(timeline, token: replayToken)
    }

    // MARK: - Links: de wachtrij

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(String(localized: "guide.demo.download.source"))
                .font(.brandMono(size: 9))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(.ink4)
                .guideAppear(phase, at: 0)

            // Chip en scanbalk verdwijnen zodra het bestand geland is, zodat er
            // geen gat achterblijft in het eindbeeld waar de demo op blijft staan.
            if !cleared {
                GuideFileChip(icon: "music.note", name: "ES_Golden Hour.wav")
                    .guideAppear(phase, at: 1, offset: 16)
                    .offset(x: landed ? 175 : 0, y: landed ? 24 : 0)
                    .scaleEffect(landed ? 0.6 : 1)
                    .opacity(landed ? 0 : 1)
                    .animation(.easeIn(duration: 0.7), value: landed)
                    .zIndex(1)

                scanBar
            }

            badges

            pathChips
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(GuideMotion.appear, value: cleared)
    }

    private var scanBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.line2)
            Capsule()
                .fill(Color.brandBurntPeach)
                .frame(width: phase >= 2 ? 132 : 0)
                .animation(GuideMotion.fill.delay(0.05), value: phase >= 2)
        }
        .frame(width: 132, height: 3)
        .opacity(phase == 2 ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    private var badges: some View {
        HStack(spacing: 5) {
            GuideBadge(text: String(localized: "guide.demo.download.badge_music"),
                       background: .aiChipBg, foreground: .aiChipInk)
                .guideLand(phase, at: 3)
            GuideBadge(text: String(localized: "guide.demo.download.badge_mood"),
                       background: .destChipBg, foreground: .destChipInk)
                .guideLand(phase, at: 3)
                .animation(GuideMotion.land.delay(0.12), value: phase >= 3)
            GuideBadge(text: "128 BPM",
                       background: .pathNewBg, foreground: .pathNewFg)
                .guideLand(phase, at: 3)
                .animation(GuideMotion.land.delay(0.24), value: phase >= 3)
        }
        .frame(height: 17, alignment: .leading)
    }

    private var pathChips: some View {
        HStack(spacing: 4) {
            GuidePathChip(text: "PROJECT_A")
                .guideAppear(phase, at: 4)
            GuidePathSeparator()
                .guideAppear(phase, at: 4)
            GuidePathChip(text: "03_Audio")
                .guideAppear(phase, at: 4)
                .animation(GuideMotion.appear.delay(0.1), value: phase >= 4)
            GuidePathSeparator()
                .guideAppear(phase, at: 4)
            GuidePathChip(text: "01_Music")
                .guideAppear(phase, at: 4)
                .animation(GuideMotion.appear.delay(0.2), value: phase >= 4)
            GuidePathSeparator()
                .guideAppear(phase, at: 4)
            GuidePathChip(text: "Uplifting", isNew: true)
                .guideAppear(phase, at: 4)
                .animation(GuideMotion.appear.delay(0.3), value: phase >= 4)
        }
        .frame(height: 20, alignment: .leading)
    }

    // MARK: - Rechts: de mappenboom

    private var treeColumn: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 2) {
                GuideTreeRow(indent: 0, name: "PROJECT_A/")
                GuideTreeRow(indent: 1, name: "02_Footage/")
                GuideTreeRow(indent: 1, name: "03_Audio/")
                GuideTreeRow(indent: 2, name: "01_Music/")
                GuideTreeRow(indent: 3, name: "Uplifting/", highlighted: true)
                    .guideLand(phase, at: 5)
                GuideTreeRow(indent: 2, name: "03_VO/")
            }
            .padding(.horizontal, 12)

            GuidePetalBurst(active: landed, count: 8, spread: 34)
                .offset(y: 10)
        }
        .frame(width: 152)
        .frame(maxHeight: .infinity)
        .background(Color.paper1)
    }
}
