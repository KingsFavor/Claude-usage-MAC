import Foundation
import SwiftUI
import AppKit

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var snapshots: [Snapshot] = []
    @Published var plan: String?
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var needsLogin = false
    @Published var isLoggingIn = false
    @Published var availableUpdate: UpdateInfo?
    @Published var isCheckingForUpdate = false
    @Published var noUpdateNotice = false     // transient "you're up to date"

    private let service = UsageService()
    private let store = SnapshotStore()
    private let updateChecker = UpdateChecker()
    private var timer: Timer?
    private var started = false

    // Rate-limit backoff: after a 429 we hold off automatic fetches until
    // `nextAllowedFetch`, growing the delay each time. A forced (user-initiated)
    // refresh ignores the gate.
    private var backoffStep = 0
    private var nextAllowedFetch: Date?

    // Marketing version of the running build. nil when launched as a bare
    // binary (dev), in which case we skip update checks entirely.
    private var appVersion: String? {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    /// Version string for display (nil for a bare dev binary).
    var displayVersion: String? { appVersion }

    // Poll interval in seconds (persisted). Clamped to a sane range.
    // Default 5 min: the usage windows (5h / weekly) change slowly, and frequent
    // polling of api.anthropic.com trips Cloudflare's per-IP rate limit (429).
    var pollInterval: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "pollIntervalSeconds")
            return v == 0 ? 300 : min(max(v, 60), 1800)  // clamp legacy/aggressive values
        }
        set {
            let clamped = min(max(newValue, 60), 1800)
            UserDefaults.standard.set(clamped, forKey: "pollIntervalSeconds")
            objectWillChange.send()
            scheduleTimer()
        }
    }

    // Command a user can copy to update via Homebrew (includes `brew update`).
    let updateCommand = "brew update && brew upgrade --cask claude-usage"
    @Published var commandCopied = false

    func copyUpdateCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(updateCommand, forType: .string)
        commandCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            commandCopied = false
        }
    }

    // Launch-at-login (macOS login item). Reflects the live SMAppService status.
    @Published var launchAtLogin = LoginItem.isEnabled
    var launchAtLoginSupported: Bool { LoginItem.isSupported }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchAtLogin = LoginItem.isEnabled  // re-read: reflects actual state on failure
    }

    init() {
        // Register as a login item on first run so the app starts at boot.
        LoginItem.enableOnFirstRunIfNeeded()
        launchAtLogin = LoginItem.isEnabled  // reflect any first-run registration
        snapshots = store.snapshots
        let loaded = KeychainAuth.load()
        plan = loaded?.creds.subscriptionType
        needsLogin = (loaded == nil)
        // Watch for in-place updates from app launch — independent of whether
        // the user ever opens the menu (start() only runs on first open).
        scheduleUpdateWatch()
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await refresh() }
        scheduleTimer()
        observeWake()
    }

    // Refresh promptly when the Mac wakes: the repeating Timer is unreliable
    // across sleep, and right after wake the token may be expired and the
    // network not yet ready — so refresh now and retry shortly after.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refreshAfterWake() }
        }
    }

    private func refreshAfterWake() async {
        relaunchIfUpdated()  // may have been upgraded (brew) while asleep
        await refresh()
        // Network stack often lags a few seconds behind wake; try once more.
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        await refresh()
    }

    // MARK: - Auto-restart after an in-place update (e.g. `brew upgrade --cask`)
    // Homebrew replaces the .app bundle underneath the running process, so the
    // old version keeps running until relaunched. Watch the on-disk bundle
    // version; when it no longer matches the running one, relaunch into it.

    private let launchVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    private var updateWatchTimer: Timer?
    private var relaunching = false

    private func scheduleUpdateWatch() {
        guard launchVersion != nil else { return }  // dev binary → skip
        updateWatchTimer?.invalidate()
        updateWatchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.relaunchIfUpdated() }
        }
    }

    private func relaunchIfUpdated() {
        // Don't yank the app mid-login (would kill the OAuth loopback server).
        guard !relaunching, !isLoggingIn, let launchVersion else { return }
        let plistPath = Bundle.main.bundlePath + "/Contents/Info.plist"
        guard let dict = NSDictionary(contentsOfFile: plistPath),
              let onDisk = dict["CFBundleShortVersionString"] as? String,
              !onDisk.isEmpty, onDisk != launchVersion else { return }

        relaunching = true
        // Relaunch the (now-updated) bundle, but only once THIS process has
        // fully exited — otherwise `open` just reactivates the dying instance
        // and no new one launches.
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(path)\""]
        try? proc.run()
        NSApp.terminate(nil)
    }

    /// The session is no longer valid (token expired / credentials gone).
    /// Clear the cached data so the UI actually shows the login state instead
    /// of freezing on the last fetched numbers.
    private func markLoggedOut() {
        needsLogin = true
        usage = nil
        plan = nil
        lastUpdated = nil
        errorMessage = nil
    }

    /// Quietly check GitHub for a newer release, at most once every 6 hours.
    /// Surfaces `availableUpdate` for a dismissible in-panel banner — no
    /// notifications, no dialogs, no auto-download.
    func checkForUpdatesIfDue(force: Bool = false) {
        guard let current = appVersion else { return }  // dev binary → skip
        let key = "lastUpdateCheckAt"
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: key)
        if !force, last != 0, now - last < 6 * 3600 { return }

        Task {
            let info = await updateChecker.check(currentVersion: current)
            UserDefaults.standard.set(now, forKey: key)
            guard let info else { return }
            // Respect a user who dismissed this exact version.
            if UserDefaults.standard.string(forKey: "dismissedUpdateVersion") == info.version { return }
            availableUpdate = info
        }
    }

    /// User-initiated check. Bypasses the 6h throttle and any prior dismissal,
    /// and gives explicit feedback: the banner if newer, else a brief "up to
    /// date" note. No dialogs, no notifications.
    func checkForUpdatesNow() async {
        guard !isCheckingForUpdate else { return }
        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheckAt")
        guard let current = appVersion,
              let info = await updateChecker.check(currentVersion: current) else {
            availableUpdate = nil
            flashNoUpdateNotice()
            return
        }
        // Explicit check → show it even if this version was dismissed before.
        UserDefaults.standard.removeObject(forKey: "dismissedUpdateVersion")
        availableUpdate = info
    }

    private func flashNoUpdateNotice() {
        noUpdateNotice = true
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            noUpdateNotice = false
        }
    }

    /// Hide the banner and remember not to nag about this version again.
    func dismissUpdate() {
        if let v = availableUpdate?.version {
            UserDefaults.standard.set(v, forKey: "dismissedUpdateVersion")
        }
        availableUpdate = nil
    }

    func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            let creds = try await OAuthLogin().run()
            KeychainAuth.saveAppCreds(creds)
            needsLogin = false
            errorMessage = nil
            backoffStep = 0
            nextAllowedFetch = nil
            await refresh(force: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        KeychainAuth.deleteAppCreds()
        usage = nil
        plan = nil
        lastUpdated = nil
        errorMessage = nil
        // Fall back to Claude Code creds if present; else require login.
        needsLogin = (KeychainAuth.load() == nil)
        if !needsLogin { Task { await refresh() } }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh(force: Bool = false) async {
        checkForUpdatesIfDue()  // throttled to once / 6h; independent of login
        guard !needsLogin else { return }
        // Respect rate-limit backoff for automatic polls; a user tap forces through.
        if !force, let next = nextAllowedFetch, Date() < next { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let u = try await service.fetchUsage()
            usage = u
            errorMessage = nil
            needsLogin = false
            lastUpdated = Date()
            nextAllowedFetch = nil
            backoffStep = 0
            if let p = KeychainAuth.load()?.creds.subscriptionType { plan = p }

            let snap = Snapshot(
                timestamp: Date(),
                fiveHour: u.fiveHour?.utilization,
                sevenDay: u.sevenDay?.utilization,
                sevenDayOpus: u.sevenDayOpus?.utilization
            )
            store.append(snap)
            snapshots = store.snapshots
        } catch UsageServiceError.noCredentials {
            markLoggedOut()
        } catch UsageServiceError.unauthorized {
            // Token invalid and refresh failed → require re-login.
            markLoggedOut()
        } catch let UsageServiceError.rateLimited(retryAfter) {
            applyBackoff(retryAfter: retryAfter)
        } catch {
            // Transient (network) failure: keep the last data but flag it so the
            // UI can show an "offline" note instead of pretending it's current.
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // Rate limited (429): hold off automatic fetches and grow the delay so we
    // stop hammering the endpoint. Keep any last data on screen.
    private func applyBackoff(retryAfter: Int?) {
        let base = retryAfter ?? min(1800, 60 * (1 << min(backoffStep, 5)))  // 60s → … → 1800s
        backoffStep = min(backoffStep + 1, 5)
        nextAllowedFetch = Date().addingTimeInterval(Double(base))
        let mins = max(1, Int(ceil(Double(base) / 60)))
        errorMessage = "요청이 많아 잠시 제한되었습니다.\n약 \(mins)분 후 자동으로 다시 시도합니다. (새로고침으로 즉시 재시도)"
    }
}
