import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {

    private let model: PlaybackModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let label: PassthroughHostingView<LyricLabel>
    private let settings: ItemPopover
    private let tips: ItemPopover

    private static let menuGap: CGFloat = 1

    init(model: PlaybackModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.label = PassthroughHostingView(rootView: LyricLabel(
            text: model.lineText, boxWidth: model.lyricBoxWidth, opacity: model.displayState.opacity))
        self.settings = ItemPopover(SettingsView(model: model))
        self.tips = ItemPopover(TipsView())
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = MenuBarMetrics.menuWidth

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.title = ""
            button.imagePosition = .noImage
            label.sizingOptions = []
            label.frame = button.bounds
            label.autoresizingMask = [.width, .height]
            button.addSubview(label)
        }

        render()
        observe()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let box = model.lyricBoxWidth
        let text = model.lineText

        statusItem.length = box
        label.rootView = LyricLabel(text: text, boxWidth: box, opacity: model.displayState.opacity)
        button.setAccessibilityLabel(text)

        logFit(text: text, box: box, window: button.window)
    }

    private func logFit(text: String, box: CGFloat, window: NSWindow?) {
        let state = model.displayState
        let size = LyricText.fittedFontSize(for: text, boxWidth: box)
        let drawn = MenuBarMetrics.textWidth(text, fontSize: size)
        let overflow = drawn - box

        if overflow > 0.5 {
            FitLog.render.error("""
                clipped state=\(state.rawValue, privacy: .public) \
                box=\(FitLog.points(box), privacy: .public) \
                chars=\(text.count, privacy: .public) \
                fontSize=\(size, format: .fixed(precision: 1), privacy: .public) \
                floor=\(MenuBarMetrics.minimumFontSize, format: .fixed(precision: 1), privacy: .public) \
                drawnWidth=\(FitLog.points(drawn), privacy: .public) \
                overflow=\(FitLog.points(overflow), privacy: .public) \
                \(FitLog.geometry(window?.frame), privacy: .public)
                """)
            return
        }

        FitLog.render.debug("""
            drew state=\(state.rawValue, privacy: .public) \
            box=\(FitLog.points(box), privacy: .public) \
            chars=\(text.count, privacy: .public) \
            fontSize=\(size, format: .fixed(precision: 1), privacy: .public) \
            drawnWidth=\(FitLog.points(drawn), privacy: .public) \
            headroom=\(FitLog.points(-overflow), privacy: .public) \
            \(FitLog.geometry(window?.frame), privacy: .public)
            """)
    }

    private func observe() {
        withObservationTracking {
            _ = model.lineText
            _ = model.lyricBoxWidth
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

extension StatusItemController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = model.headerLines
        menu.addItem(MenuHeader.item(title: header.title, detail: header.detail))
        menu.addItem(.separator())

        let hide = NSMenuItem(title: model.isHidden ? String(localized: "Show Lyrics") : String(localized: "Hide Lyrics"),
                              action: #selector(toggleHidden), keyEquivalent: "p")
        hide.target = self
        menu.addItem(hide)

        let preferences = NSMenuItem(title: String(localized: "Settings…"),
                                     action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let help = NSMenuItem(title: String(localized: "Tips…"),
                              action: #selector(openTips), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        if model.displayState == .denied {
            let automation = NSMenuItem(title: String(localized: "Open Automation Settings…"),
                                        action: #selector(openAutomation), keyEquivalent: "")
            automation.target = self
            menu.addItem(automation)
        }

        menu.addItem(.separator())

        if let release = model.availableUpdate {
            let update = NSMenuItem(title: String(localized: "Update Available (\(release.tagName))…"),
                                    action: #selector(openUpdate), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }

        let version = NSMenuItem(title: String(localized: "LyricBar \(model.appVersion)"),
                                 action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let quit = NSMenuItem(title: String(localized: "Quit LyricBar"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func toggleHidden() {
        model.isHidden.toggle()
    }

    @objc private func showMenu() {
        guard let button = statusItem.button else { return }
        guard let window = button.window else { return }
        let origin = NSPoint(x: window.frame.minX, y: window.frame.minY - Self.menuGap)
        button.highlight(true)
        menu.popUp(positioning: nil, at: origin, in: nil)
        button.highlight(false)
    }

    @objc private func openTips() {
        guard let button = statusItem.button else { return }
        tips.toggle(from: button)
    }

    @objc private func openSettings() {
        guard let button = statusItem.button else { return }
        settings.toggle(from: button)
    }

    @objc private func openUpdate() {
        model.openAvailableUpdate()
    }

    @objc private func openAutomation() {
        model.openAutomationSettings()
    }
}
