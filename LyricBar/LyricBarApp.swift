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
