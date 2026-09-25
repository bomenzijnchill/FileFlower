import SwiftUI

/// De schil van de gids: hoofdstukzijbalk, inhoud en voetnavigatie.
///
/// Deze view leest alleen — hij schrijft nooit naar `AppState.config`. Daarom is
/// opnieuw bekijken gratis, in tegenstelling tot "Reset setup" bij de wizard.
struct GuideView: View {
    let onClose: () -> Void

    @State private var current: GuideChapter = GuideManager.shared.lastChapter
    @State private var replayToken = 0
    @State private var progress: Double = GuideManager.shared.progress
    @State private var seen: Set<String> = GuideManager.shared.seenChapters

    private var chapters: [GuideChapter] { GuideChapter.enabled }
    private var isLast: Bool { current.index == chapters.count - 1 }
    private var isFirst: Bool { current.index == 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
            Divider()
            footer
        }
        .background(Color.cardBg)
        .onAppear { markSeen(current) }
    }

    // MARK: - Zijbalk

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "guide.chapter_counter \(current.index + 1) \(chapters.count)"))
                    .font(.brandMono(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundColor(.ink3)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.line2)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.brandBurntPeach)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            ForEach(chapters) { chapter in
                chapterButton(chapter)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 212)
        .background(Color.paper1)
    }

    private func chapterButton(_ chapter: GuideChapter) -> some View {
        let isCurrent = chapter == current
        let isSeen = seen.contains(chapter.rawValue)

        return Button {
            go(to: chapter)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(numberBackground(isCurrent: isCurrent, isSeen: isSeen))
                    if !isCurrent && isSeen {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.fsStepDoneInk)
                    } else {
                        Text("\(chapter.index + 1)")
                            .font(.brandMono(size: 9.5, weight: .semibold))
                            .foregroundColor(isCurrent ? .fsStepActiveInk : .fsStepIdleInk)
                    }
                }
                .frame(width: 19, height: 19)

                Text(String(localized: chapter.navKey))
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .ink : .ink2)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 7).fill(Color.cardBg)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func numberBackground(isCurrent: Bool, isSeen: Bool) -> Color {
        if isCurrent { return .fsStepActiveBg }
        if isSeen { return .fsStepDoneBg }
        return .fsStepIdleBg
    }

    // MARK: - Inhoud

    private var content: some View {
        ScrollView {
            GuideChapterView(
                chapter: current,
                replayToken: replayToken,
                onReplay: { replayToken += 1 }
            )
            .padding(.horizontal, 30)
            .padding(.top, 26)
            .padding(.bottom, 24)
            .id(current)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cardBg)
    }

    // MARK: - Voetnavigatie

    private var footer: some View {
        HStack {
            Button(String(localized: "common.previous")) {
                if let prev = chapters[safe: current.index - 1] { go(to: prev) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isFirst)

            Spacer()

            HStack(spacing: 5) {
                ForEach(chapters) { chapter in
                    Capsule()
                        .fill(chapter == current ? Color.brandBurntPeach : Color.line2)
                        .frame(width: chapter == current ? 16 : 5, height: 5)
                        .animation(.easeInOut(duration: 0.25), value: current)
                }
            }

            Spacer()

            Button(isLast ? String(localized: "guide.finish") : String(localized: "common.next")) {
                if isLast {
                    GuideManager.shared.markGuideFinished()
                    onClose()
                } else if let next = chapters[safe: current.index + 1] {
                    go(to: next)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color.paper1)
    }

    // MARK: - Navigatie

    private func go(to chapter: GuideChapter) {
        guard chapter != current else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            current = chapter
        }
        markSeen(chapter)
    }

    private func markSeen(_ chapter: GuideChapter) {
        GuideManager.shared.markSeen(chapter)
        seen = GuideManager.shared.seenChapters
        withAnimation(GuideMotion.fill) {
            progress = GuideManager.shared.progress
        }
    }
}

// MARK: - Hulp

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
