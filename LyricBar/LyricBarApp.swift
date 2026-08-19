import SwiftUI
import AppKit

@main
struct LyricBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PlaybackModel.isRunningTests else { return }
        controller = StatusItemController(model: PlaybackModel())
    }
}

struct LyricPopover: View {
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
            Button(model.isHidden ? "Show Lyrics" : "Hide Lyrics") {
                model.isHidden.toggle()
            }
            .keyboardShortcut("p")

            Toggle("Open at Login", isOn: $model.loginEnabled)
                .onAppear { model.refreshLoginState() }
                .disabled(!model.loginSupported)

            Picker("Width", selection: $model.widthPreference) {
                ForEach(LyricWidth.allCases, id: \.self) { width in
                    Text(width.title).tag(width)
                }
            }

            if model.displayState == .denied {
                Button("Open Automation Settings…") {
                    model.openAutomationSettings()
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
