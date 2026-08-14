import ServiceManagement

// MARK: - Login item
//
// The whole launchctl / plist dance from the old bare-executable build is gone.
// Because this is now a real signed .app bundle, `SMAppService.mainApp` manages
// "open at login" natively: the system tracks approval, shows the app under
// System Settings > General > Login Items, and there is no KeepAlive to fight —
// so quitting no longer has to disable the login setting to make Quit stick.

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Throws so the caller can
    /// surface failures (e.g. the user must approve in System Settings).
    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
