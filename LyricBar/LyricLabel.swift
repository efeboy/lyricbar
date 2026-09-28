import SwiftUI

struct LyricLabel: View {

    static let lineCrossfade: Double = 0.18
    static let stateFade: Double = 0.35

    let text: String
    let boxWidth: CGFloat
    let opacity: Double

    var body: some View {
        ZStack {
            Text(text)
                .font(font)
                .foregroundStyle(.primary)
                .fixedSize()
                .id(text)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: Self.lineCrossfade), value: text)
        .opacity(opacity)
        .animation(.easeInOut(duration: Self.stateFade), value: opacity)
        .frame(width: boxWidth)
        .frame(maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var font: Font {
        let size = LyricText.fittedFontSize(for: text, boxWidth: boxWidth)
        return Font(MenuBarMetrics.font(ofSize: size) as CTFont)
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
