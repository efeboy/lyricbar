import AppKit
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {

    private static let lineCrossfade: CFTimeInterval = 0.18
    private static let stateFade: TimeInterval = 0.35
    private static let crossfadeKey = "lyric"

    private let model: PlaybackModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    private var shownText: String?
    private var shownOpacity: Double?

    init(model: PlaybackModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: LyricPopover(model: model))

        if let button = statusItem.button {
            button.wantsLayer = true
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

        MenuBarFit.itemWindow = button.window
        statusItem.length = box

        if let shownText, shownText != text {
            let crossfade = CATransition()
            crossfade.type = .fade
            crossfade.duration = Self.lineCrossfade
            button.layer?.add(crossfade, forKey: Self.crossfadeKey)
        }
        button.attributedTitle = LyricText.attributed(text: text, boxWidth: box)
        button.setAccessibilityLabel(text)
        shownText = text

        fade(button, to: model.displayState.opacity)
    }

    private func fade(_ button: NSStatusBarButton, to opacity: Double) {
        defer { shownOpacity = opacity }
        guard let shownOpacity else {
            button.alphaValue = opacity
            return
        }
        guard shownOpacity != opacity else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.stateFade
            button.animator().alphaValue = opacity
        }
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
