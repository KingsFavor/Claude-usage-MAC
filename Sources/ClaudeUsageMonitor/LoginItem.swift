import Foundation
import ServiceManagement

// MARK: - Launch at login
//
// Registers the app as a macOS login item so it starts automatically at boot /
// user login. Uses SMAppService (macOS 13+, and we target 14+), which registers
// the currently-running .app bundle — no separate helper target or LaunchAgent
// plist needed. Only meaningful for the packaged .app; a bare dev binary has no
// bundle to register, so we no-op there.
enum LoginItem {
    // A registerable bundle exists only when running from an .app (not a bare
    // `swift run` binary). Bundle identifier is our proxy for "packaged".
    private static var isPackaged: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        guard isPackaged else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Available (togglable) only for a real packaged app.
    static var isSupported: Bool { isPackaged }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isPackaged else { return false }
        do {
            if enabled {
                // Idempotent-ish: registering an already-enabled service throws,
                // so skip when already on.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[LoginItem] setEnabled(\(enabled)) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Turn on launch-at-login the first time the app runs, so it "just works"
    /// out of the box. Runs only once — after that the user's toggle wins, even
    /// if they turn it off. Skipped if macOS already reports it enabled.
    static func enableOnFirstRunIfNeeded() {
        guard isPackaged else { return }
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: key)
    }
}
