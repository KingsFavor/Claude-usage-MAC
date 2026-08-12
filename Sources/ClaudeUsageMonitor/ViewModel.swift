import Foundation
import SwiftUI

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

    private let service = UsageService()
    private let store = SnapshotStore()
    private let updateChecker = UpdateChecker()
    private var timer: Timer?
    private var started = false

    // Marketing version of the running build. nil when launched as a bare
    // binary (dev), in which case we skip update checks entirely.
    private var appVersion: String? {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    // Poll interval in seconds (persisted). Clamped to a sane range.
    var pollInterval: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "pollIntervalSeconds")
            return v == 0 ? 60 : v
        }
        set {
            let clamped = min(max(newValue, 15), 600)
            UserDefaults.standard.set(clamped, forKey: "pollIntervalSeconds")
            objectWillChange.send()
            scheduleTimer()
        }
    }

    init() {
        snapshots = store.snapshots
        let loaded = KeychainAuth.load()
        plan = loaded?.creds.subscriptionType
        needsLogin = (loaded == nil)
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await refresh() }
        scheduleTimer()
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
            await refresh()
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

    func refresh() async {
        checkForUpdatesIfDue()  // throttled to once / 6h; independent of login
        guard !needsLogin else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let u = try await service.fetchUsage()
            usage = u
            errorMessage = nil
            needsLogin = false
            lastUpdated = Date()
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
            needsLogin = true
            errorMessage = nil
        } catch UsageServiceError.unauthorized {
            // Token invalid and refresh failed → require re-login.
            needsLogin = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
