import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {

    private let model: PlaybackModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let label: PassthroughHostingView<LyricLabel>

    init(model: PlaybackModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.label = PassthroughHostingView(rootView: LyricLabel(
            text: model.lineText, boxWidth: model.boxWidth, opacity: model.displayState.opacity))
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if let button = statusItem.button {
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
        let box = model.boxWidth
        let text = model.lineText

        MenuBarFit.itemWindow = button.window
        statusItem.length = box
        label.rootView = LyricLabel(text: text, boxWidth: box, opacity: model.displayState.opacity)
        button.setAccessibilityLabel(text)

        logFit(text: text, box: box, window: button.window)
    }

    private func logFit(text: String, box: CGFloat, window: NSWindow?) {
        let state = model.displayState
        let lyricBox = model.lyricBoxWidth
        let probing = box != lyricBox
        let size = LyricText.fittedFontSize(for: text, boxWidth: box)
        let drawn = MenuBarMetrics.textWidth(text, fontSize: size)
        let overflow = drawn - box

        if overflow > 0.5 {
            FitLog.render.error("""
                clipped state=\(state.rawValue, privacy: .public) \
                box=\(FitLog.points(box), privacy: .public) \
                lyricBox=\(FitLog.points(lyricBox), privacy: .public) \
                fittedWidth=\(FitLog.points(self.model.fittedWidth), privacy: .public) \
                chars=\(text.count, privacy: .public) \
                fontSize=\(size, format: .fixed(precision: 1), privacy: .public) \
                floor=\(MenuBarMetrics.minimumFontSize, format: .fixed(precision: 1), privacy: .public) \
                drawnWidth=\(FitLog.points(drawn), privacy: .public) \
                overflow=\(FitLog.points(overflow), privacy: .public) \
                probing=\(probing, privacy: .public) \
                \(FitLog.geometry(window?.frame), privacy: .public)
                """)
            return
        }

        FitLog.render.debug("""
            drew state=\(state.rawValue, privacy: .public) \
            box=\(FitLog.points(box), privacy: .public) \
            lyricBox=\(FitLog.points(lyricBox), privacy: .public) \
            chars=\(text.count, privacy: .public) \
            fontSize=\(size, format: .fixed(precision: 1), privacy: .public) \
            drawnWidth=\(FitLog.points(drawn), privacy: .public) \
            headroom=\(FitLog.points(-overflow), privacy: .public) \
            probing=\(probing, privacy: .public) \
            \(FitLog.geometry(window?.frame), privacy: .public)
            """)
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

extension StatusItemController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshLoginState()
        menu.removeAllItems()

        let status = NSMenuItem(title: model.header, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let hide = NSMenuItem(title: model.isHidden ? String(localized: "Show Lyrics") : String(localized: "Hide Lyrics"),
                              action: #selector(toggleHidden), keyEquivalent: "p")
        hide.target = self
        menu.addItem(hide)

        let login = NSMenuItem(title: String(localized: "Open at Login"),
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = model.loginEnabled ? .on : .off
        login.isEnabled = model.loginSupported
        menu.addItem(login)

        menu.addItem(widthItem())

        if model.displayState == .denied {
            let automation = NSMenuItem(title: String(localized: "Open Automation Settings…"),
                                        action: #selector(openAutomation), keyEquivalent: "")
            automation.target = self
            menu.addItem(automation)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "Quit LyricBar"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func widthItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Width"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for band in LyricWidth.allCases {
            let row = NSMenuItem(title: band.title,
                                 action: #selector(selectWidth(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = band
            row.state = model.widthPreference == band ? .on : .off
            submenu.addItem(row)
        }
        item.submenu = submenu
        return item
    }

    @objc private func toggleHidden() {
        model.isHidden.toggle()
    }

    @objc private func toggleLogin() {
        model.loginEnabled.toggle()
    }

    @objc private func selectWidth(_ sender: NSMenuItem) {
        guard let band = sender.representedObject as? LyricWidth else { return }
        model.widthPreference = band
    }

    @objc private func openAutomation() {
        model.openAutomationSettings()
    }
}
