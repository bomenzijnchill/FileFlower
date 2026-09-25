import SwiftUI

// MARK: - Demo-podium

/// Het omkaderde vlak waarin een demo speelt, met herhaalknop en onderschrift.
struct GuideDemoStage<Content: View>: View {
    let caption: String
    let onReplay: () -> Void
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 196)
                    .background(Color.paper0)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Color.line, lineWidth: 1)
                    )

                Button(action: onReplay) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ink3)
                        .frame(width: 24, height: 24)
                        .background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.line2, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(8)
                .opacity(hovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: hovering)
                .help(String(localized: "guide.demo.replay"))
            }
            .onHover { hovering = $0 }

            Text(caption)
                .font(.brandMono(size: 9.5, weight: .medium))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(.ink4)
        }
    }
}

// MARK: - "Waarom dit bestaat"

/// Groene strook met de reden achter een hoofdstuk.
struct GuideWhyStrip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11))
                .foregroundColor(.destChipInk)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.destChipBg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Uitklapper met de topics

/// "Meer hierover" — de verdieping onder elk hoofdstuk.
struct GuideDeepDive: View {
    let topics: [GuideTopic]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.bottom, 11)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(String(localized: "guide.deep_dive"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.brandBurntPeach)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(topics) { topic in
                        GuideTopicRow(topic: topic)
                    }
                }
                .padding(.top, 11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Eén regel in de verdieping: titel plus toelichting.
struct GuideTopicRow: View {
    let topic: GuideTopic

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.ink4)
                .frame(width: 4, height: 4)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: topic.titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.ink)
                Text(String(localized: topic.leadKey))
                    .font(.system(size: 12.5))
                    .foregroundColor(.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Demo-atomen

/// Bestandschip zoals in de wachtrij.
struct GuideFileChip: View {
    let icon: String
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.brandBurntPeach)
            Text(name)
                .font(.brandMono(size: 10.5))
                .foregroundColor(.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.line2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

/// Klein gekleurd label, bijv. "Muziek" of "Uplifting".
struct GuideBadge: View {
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.brandMono(size: 9, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Padsegment. `isNew` gebruikt de gestippelde peach-stijl van de padeditor.
struct GuidePathChip: View {
    let text: String
    var isNew: Bool = false

    var body: some View {
        Text(text)
            .font(.brandMono(size: 10))
            .foregroundColor(isNew ? .pathNewFg : .pathExistFg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isNew ? Color.pathNewBg : Color.pathExistBg)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                if isNew {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.pathNewBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
    }
}

/// Scheidingsteken tussen padsegmenten.
struct GuidePathSeparator: View {
    var body: some View {
        Text("›")
            .font(.brandMono(size: 10))
            .foregroundColor(.ink4)
    }
}

/// Eén regel in een mappenboom.
struct GuideTreeRow: View {
    let indent: Int
    let name: String
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(String(repeating: "  ", count: indent))
                .font(.brandMono(size: 10.5))
            Text(name)
                .font(.brandMono(size: 10.5, weight: highlighted ? .semibold : .regular))
                .foregroundColor(highlighted ? .destChipInk : .ink2)
                .padding(.horizontal, highlighted ? 5 : 0)
                .padding(.vertical, highlighted ? 1 : 0)
                .background {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 4).fill(Color.destChipBg)
                    }
                }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Bloemblaadjes

/// Bloemblaadje-uitbarsting, hergebruikt `PetalShape` uit `PetalAnimationView`
/// zodat de gids dezelfde signatuur-beweging heeft als de app zelf.
struct GuidePetalBurst: View {
    /// Speelt af zodra dit `true` wordt.
    let active: Bool
    var count: Int = 10
    var spread: CGFloat = 50

    private struct Blade: Identifiable {
        let id: Int
        let color: Color
        let size: CGFloat
        let angle: Double
        let x: CGFloat
        let y: CGFloat
        let delay: Double
        let spin: Double
        let scaleEnd: CGFloat
    }

    /// De blaadjes staan in `@State` en niet in een gewone `let`: SwiftUI maakt de
    /// struct bij élke re-render opnieuw aan (fasewissel van de demo, hover over het
    /// podium). Werden ze daar opnieuw gerandomiseerd, dan kregen ze verse `id`'s,
    /// gooide SwiftUI de lopende views weg en brak de wegwaai-animatie halverwege af.
    @State private var blades: [Blade]

    init(active: Bool, count: Int = 10, spread: CGFloat = 50) {
        self.active = active
        self.count = count
        self.spread = spread
        let palette: [Color] = [.brandPowderBlush, .petalRosePink, .petalLavender, .brandBurntPeach]
        _blades = State(initialValue: (0..<count).map { index in
            Blade(
                id: index,
                color: palette.randomElement() ?? .brandPowderBlush,
                size: CGFloat.random(in: 7...12),
                angle: Double.random(in: 0...360),
                x: CGFloat.random(in: -spread...spread),
                y: CGFloat.random(in: -110...(-60)),
                delay: Double.random(in: 0...0.3),
                spin: Double.random(in: 90...360),
                scaleEnd: CGFloat.random(in: 0.2...0.5)
            )
        })
    }

    var body: some View {
        ZStack {
            ForEach(blades) { blade in
                PetalShape()
                    .fill(blade.color)
                    .frame(width: blade.size, height: blade.size * 1.6)
                    .rotationEffect(.degrees(active ? blade.angle + blade.spin : blade.angle))
                    .offset(x: active ? blade.x : 0, y: active ? blade.y : 0)
                    .scaleEffect(active ? blade.scaleEnd : 1.0)
                    .opacity(active ? 0 : 1)
                    .animation(GuideMotion.drift.delay(blade.delay), value: active)
            }
        }
    }
}
