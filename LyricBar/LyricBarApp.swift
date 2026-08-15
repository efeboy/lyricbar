import SwiftUI
import AppKit

// MARK: - App entry point
//
// A menu-bar-only utility: `MenuBarExtra` is the whole UI. LSUIElement in the
// generated Info.plist keeps it out of the Dock and app switcher. No AppDelegate,
// no NSStatusItem, no manual menu construction — the scene and SwiftUI controls
// do all of it.
//
// The scene uses `.window` style so the click target is the lyric popover rather
// than a plain NSMenu. That is a real trade: `.menu` style would give menu rows
// for free, but it cannot show the track header and the previous/current/next
// triplet. Settings and Quit therefore live behind the popover's own pull-down,
// whose contents AppKit still renders as a genuine NSMenu.
//
// `MenuBarExtra` has NO right-click menu — in `.window` style both buttons open
// the popover, and SwiftUI exposes no secondary-menu hook. Getting true
// right-click would mean dropping back to a hand-rolled NSStatusItem, which this
// rewrite deliberately removed. Don't reintroduce it for that alone.

@main
struct LyricBarApp: App {
    @State private var model = PlaybackModel()

    var body: some Scene {
        MenuBarExtra {
            LyricPopover(model: model)
        } label: {
            LyricLabel(text: model.lineText,
                       boxWidth: model.boxWidth,
                       opacity: model.displayState.opacity)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar label
//
// ONE FIXED BOX. `model.boxWidth` is pinned on the outer container and the icon
// and lyric are laid out inside it — the box is the thing that never changes.
//
// Pinning the OUTER frame rather than the inner Text is the load-bearing detail:
// it makes the item's width independent of what the icon and text each report.
// Sizing the Text and letting the HStack add itself up leaves the total at the
// mercy of the symbol's own metrics.
//
// Every state — playing, instrumental, no lyrics, paused, idle — therefore
// occupies exactly the same width, so the item never resizes, never shoves its
// neighbours sideways, and never hides them by growing. Auto-sizing to the line
// would twitch the whole menu bar on every lyric: line-to-line width change
// averages 67pt and reaches 404pt. The states are told apart by opacity.
//
// The Text is laid out even when empty, and `LyricReflow` has already split the
// line to fit `model.lyricWidth`, so truncation here is only a last resort for
// a single word wider than the whole budget.

// Takes plain values rather than the model so a test can drive every state
// directly and measure that the box never changes width.
struct LyricLabel: View {
    var text: String
    var boxWidth: CGFloat
    var opacity: Double

    var body: some View {
        HStack(spacing: MenuBarMetrics.iconGap) {
            Image(systemName: "quote.closing")
                .frame(width: MenuBarMetrics.iconWidth)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: boxWidth, alignment: .leading)
        .opacity(opacity)
    }
}

// MARK: - Popover
//
// Lyrics and the song, nothing else. This is a lyrics-only tool: no transport,
// no seek, no progress. Everything that is not a lyric lives in the pull-down.

private struct LyricPopover: View {
    var model: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            trackHeader
            Divider()
            lyricTriplet
        }
        .padding(14)
        .frame(width: 320)
    }

    private var trackHeader: some View {
        HStack(spacing: 12) {
            // The bridges are read-only and expose no artwork, so this is an
            // honest placeholder rather than a promise of album art.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.trackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.trackArtist)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(model.trackSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            OptionsMenu(model: model)
        }
    }

    /// Fixed height, so the popover does not resize as the current line wraps —
    /// the same anti-jitter reasoning as the menu bar item's fixed width.
    private var lyricTriplet: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.previousLine)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(model.currentLine)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.nextLine)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 108, maxHeight: 108, alignment: .leading)
    }
}

// MARK: - Options pull-down
//
// A SwiftUI `Menu`, so AppKit renders the contents as a real NSMenu: checkmarks,
// submenus, and ⌘-shortcut glyphs all come from the system.

private struct OptionsMenu: View {
    var model: PlaybackModel

    // Labels describe responsiveness only. Measured CPU is dominated by AppKit
    // status-item overhead, not the poll loop, so per-rate CPU claims would be
    // misleading.
    private static let speeds: [(ms: Int, label: String)] = [
        (200, "Smooth (200 ms)"),
        (500, "Balanced (500 ms)"),
        (1000, "Relaxed (1 s)"),
    ]

    /// "Standard (~44 characters)". The count is a readout of the fixed box, not
    /// an input to it — a character budget cannot bound a proportional font.
    private static func widthLabel(_ width: LyricWidth) -> String {
        let text = MenuBarMetrics.textWidth(width)
        return "\(width.title) (~\(MenuBarMetrics.typicalCharacters(inTextWidth: text)) characters)"
    }

    var body: some View {
        Menu {
            Button(model.isPaused ? "Resume Lyrics" : "Pause Lyrics") {
                model.togglePause()
            }
            .keyboardShortcut("p")

            Divider()

            Toggle("Open at Login", isOn: Binding(
                get: { model.loginEnabled },
                set: { model.setLogin($0) }))
                .onAppear { model.refreshLoginState() }

            Menu("Width") {
                ForEach(LyricWidth.allCases, id: \.self) { width in
                    Toggle(Self.widthLabel(width), isOn: Binding(
                        get: { model.widthPreference == width },
                        set: { if $0 { model.setWidth(width) } }))
                }
            }

            Menu("Update Speed") {
                ForEach(Self.speeds, id: \.ms) { speed in
                    Toggle(speed.label, isOn: Binding(
                        get: { model.tickInterval == Double(speed.ms) / 1000.0 },
                        set: { if $0 { model.setTickInterval(Double(speed.ms) / 1000.0) } }))
                }
            }

            Divider()

            Button("Quit LyricBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
