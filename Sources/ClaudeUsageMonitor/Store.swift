import Foundation

// Persists polled snapshots to Application Support so the burst graph survives
// restarts. Prunes anything older than the retention window.
final class SnapshotStore {
    private let fileURL: URL
    private let retention: TimeInterval = 30 * 24 * 3600   // 30 days
    private(set) var snapshots: [Snapshot] = []

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageMonitor", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("snapshots.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let arr = try? JSONDecoder().decode([Snapshot].self, from: data) else { return }
        snapshots = arr
    }

    func append(_ snap: Snapshot) {
        snapshots.append(snap)
        let cutoff = Date().addingTimeInterval(-retention)
        snapshots.removeAll { $0.timestamp < cutoff }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
