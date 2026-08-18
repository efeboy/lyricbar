import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {

    private let model: PlaybackModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(model: PlaybackModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: LyricPopover(model: model))

        if let button = statusItem.button {
            button.imagePosition = .noImage
            button.target = self
            button.action = #selector(togglePopover)
        }

        render()
        observe()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let box = model.boxWidth
        let text = model.lineText

        statusItem.length = box
        button.attributedTitle = LyricText.attributed(text: text,
                                                      boxWidth: box,
                                                      alpha: model.displayState.opacity)
        button.setAccessibilityLabel(text)
    }

    private func observe() {
        withObservationTracking {
            _ = model.lineText
            _ = model.boxWidth
            _ = model.displayState
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.render()
                self.observe()
            }
        }
    }
}
