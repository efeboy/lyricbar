import SwiftUI

struct TipsView: View {

    private static let width: CGFloat = 300

    private static var tips: [(symbol: String, text: String)] {
        [
            ("command", String(localized: "Hold ⌘ and drag the lyric to move it along the menu bar.")),
            ("chevron.left.2", String(localized: "If the lyric disappears, the menu bar is full. Click the arrow beside the notch, or pick a narrower width in Settings.")),
            ("eye.slash", String(localized: "⌘P hides the lyric without quitting. Choose Show Lyrics to bring it back.")),
            ("music.note", String(localized: "♪ means there is nothing to sing right now: an instrumental part, a pause, or a song without synced lyrics.")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Tips"))
                .font(.headline)
            ForEach(Self.tips, id: \.symbol) { tip in
                Label {
                    Text(tip.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: tip.symbol)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: Self.width, alignment: .leading)
    }
}
