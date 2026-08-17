import Foundation
import ServiceManagement

enum LoginItem {

    private static let buildOutputMarkers = ["/DerivedData/", "/Build/Products/"]

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

    static func setEnabled(_ on: Bool) throws {
        guard isSupported else { return }
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
