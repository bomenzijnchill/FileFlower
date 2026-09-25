import SwiftUI

/// Rendert één hoofdstuk: kop, lead, demo, "waarom"-strook en de verdieping.
/// Elk hoofdstuk heeft bewust dezelfde opbouw — die herhaling houdt de tour leesbaar.
struct GuideChapterView: View {
    let chapter: GuideChapter
    let replayToken: Int
    let onReplay: () -> Void

    private var topics: [GuideTopic] { GuideTopic.topics(for: chapter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(String(localized: "guide.chapter_counter \(chapter.index + 1) \(GuideChapter.enabled.count)"))
                .font(.brandMono(size: 10, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundColor(.ink3)

            Text(String(localized: chapter.titleKey))
                .font(.brandSerifItalic(size: 29))
                .foregroundColor(.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: chapter.leadKey))
                .font(.system(size: 14.5))
                .foregroundColor(.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let demo = chapter.demo {
                GuideDemoStage(
                    caption: String(localized: chapter.demoCaptionKey),
                    onReplay: onReplay
                ) {
                    GuideDemoView(id: demo, replayToken: replayToken)
                }
            }

            GuideWhyStrip(text: String(localized: chapter.whyKey))

            if !topics.isEmpty {
                GuideDeepDive(topics: topics)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
