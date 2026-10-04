import AppKit
import SwiftUI

struct MenuHeader: View {

    let title: String
    let detail: String?

    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 4
    static let statusLines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let detail {
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(title)
                    .lineLimit(Self.statusLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Font(NSFont.menuFont(ofSize: 0)))
        .foregroundStyle(.secondary)
        .truncationMode(.tail)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: MenuBarMetrics.menuWidth, alignment: .leading)
    }

    @MainActor
    static func item(title: String, detail: String?) -> NSMenuItem {
        let host = NSHostingView(rootView: MenuHeader(title: title, detail: detail))
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        item.isEnabled = false
        item.setAccessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ", "))
        return item
    }
}
