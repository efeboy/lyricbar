import Foundation
import OSLog
import ServiceManagement

enum LoginItem {

    private static let buildOutputMarkers = ["/DerivedData/", "/Build/Products/"]
    private static let log = Logger(subsystem: "net.local.lyricbar", category: "login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isSupported: Bool {
        isStableLocation(Bundle.main.bundleURL)
    }

    static func isStableLocation(_ bundle: URL) -> Bool {
        let path = bundle.path
        return !buildOutputMarkers.contains { path.contains($0) }
    }

    static func setEnabled(_ on: Bool) {
        guard isSupported else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let code = (error as NSError).code
            log.error("""
                failed enabling=\(on, privacy: .public) \
                code=\(code, privacy: .public) \
                status=\(SMAppService.mainApp.status.rawValue, privacy: .public)
                """)
        }
    }
}
