import SwiftUI
import AppKit

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

struct LyricLabel: View {
    var text: String
    var boxWidth: CGFloat
    var opacity: Double

    var body: some View {
        Image(nsImage: LyricImage.render(text: text, boxWidth: boxWidth, alpha: opacity))
            .accessibilityLabel(text)
    }
}

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

private struct OptionsMenu: View {
    @Bindable var model: PlaybackModel

    var body: some View {
        Menu {
            Button(model.isPaused ? "Resume Lyrics" : "Pause Lyrics") {
                model.isPaused.toggle()
            }
            .keyboardShortcut("p")

            Divider()

            Toggle("Open at Login", isOn: $model.loginEnabled)
                .onAppear { model.refreshLoginState() }
                .disabled(!model.loginSupported)

            Picker("Width", selection: $model.widthPreference) {
                ForEach(LyricWidth.allCases, id: \.self) { width in
                    Text(label(for: width)).tag(width)
                }
            }

            Picker("Update Speed", selection: $model.updateSpeed) {
                ForEach(UpdateSpeed.allCases, id: \.self) { speed in
                    Text(speed.title).tag(speed)
                }
            }

            Divider()

            Button("Open Automation Settings…") {
                model.openAutomationSettings()
            }

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

    private func label(for width: LyricWidth) -> String {
        let box = MenuBarMetrics.boxWidth(width, fittedWidth: model.fittedWidth)
        return "\(width.title) (~\(MenuBarMetrics.typicalCharacters(inBoxWidth: box)) characters)"
    }
}
