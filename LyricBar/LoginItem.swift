import Foundation
import ServiceManagement

enum LoginItem {

    private static let developmentBuildMarker = "/DerivedData/"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isSupported: Bool {
        !Bundle.main.bundleURL.path.contains(developmentBuildMarker)
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
