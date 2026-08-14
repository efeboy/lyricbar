import SwiftUI
import AppKit

// MARK: - App entry point
//
// A menu-bar-only utility: `MenuBarExtra` is the whole UI. LSUIElement in the
// Info.plist keeps it out of the Dock and app switcher. No AppDelegate, no
// NSStatusItem, no manual menu construction — the scene and SwiftUI controls
// do all of it.

@main
struct LyricBarApp: App {
    @State private var model = PlaybackModel()

    var body: some Scene {
        MenuBarExtra {
            LyricMenu(model: model)
        } label: {
            LyricLabel(model: model)
        }
    }
}

// MARK: - Menu bar label
//
// The icon is the always-present, always-clickable anchor; the lyric text sits
// beside it and truncates natively (tail ellipsis) inside a fixed width, so the
// item never resizes and neighbouring menu bar icons never shift.

private struct LyricLabel: View {
    var model: PlaybackModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "quote.bubble")
            if !model.lineText.isEmpty {
                Text(model.lineText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: model.menuWidth, alignment: .leading)
            }
        }
    }
}

// MARK: - Menu contents

private struct LyricMenu: View {
    var model: PlaybackModel

    private static let widths = [40, 48, 60, 80]
    private static let speeds: [(ms: Int, label: String)] = [
        (200, "Smooth (200ms)"),
        (500, "Balanced (500ms)"),
        (1000, "Relaxed (1s)"),
    ]

    var body: some View {
        // Header: what is playing / why nothing shows. Non-interactive.
        Text(model.header)

        Divider()

        Button(model.isPaused ? "Resume lyrics" : "Pause lyrics") {
            model.togglePause()
        }
        .keyboardShortcut("p")

        Divider()

        Menu("Width") {
            ForEach(Self.widths, id: \.self) { n in
                Toggle("\(n) characters", isOn: Binding(
                    get: { model.maxChars == n },
                    set: { if $0 { model.setMaxChars(n) } }))
            }
        }

        // Labels describe responsiveness only. Measured CPU is dominated by
        // AppKit status-item overhead, not the poll loop, so per-rate CPU claims
        // would be misleading.
        Menu("Update speed") {
            ForEach(Self.speeds, id: \.ms) { speed in
                Toggle(speed.label, isOn: Binding(
                    get: { model.tickInterval == Double(speed.ms) / 1000.0 },
                    set: { if $0 { model.setTickInterval(Double(speed.ms) / 1000.0) } }))
            }
        }

        Divider()

        Toggle("Open at login", isOn: Binding(
            get: { model.loginEnabled },
            set: { model.setLogin($0) }))
            .onAppear { model.refreshLoginState() }

        Divider()

        Button("Quit LyricBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
