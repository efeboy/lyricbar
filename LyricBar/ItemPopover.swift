import AppKit
import SwiftUI

@MainActor
final class ItemPopover {

    private let popover = NSPopover()

    init(_ content: some View) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: content)
    }

    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
