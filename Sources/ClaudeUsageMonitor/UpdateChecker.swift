import Foundation

struct UpdateInfo: Equatable {
    let version: String   // e.g. "1.2.0"
    let url: URL          // release page to open
}

/// Non-intrusive update check against GitHub's latest published release.
/// Networking only — no UI, no side effects. The ViewModel decides when to run
/// this (throttled) and whether to surface the result.
struct UpdateChecker {
    static let releasesAPI = URL(string: "https://api.github.com/repos/KingsFavor/Claude-usage-MAC/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/KingsFavor/Claude-usage-MAC/releases/latest")!

    /// Returns update info only if the latest release is strictly newer than `currentVersion`.
    func check(currentVersion: String) async -> UpdateInfo? {
        var req = URLRequest(url: Self.releasesAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("claude-usage-monitor", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        struct Release: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let rel = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        if rel.draft == true || rel.prerelease == true { return nil }

        let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard isNewer(latest, than: currentVersion) else { return nil }
        let url = URL(string: rel.html_url) ?? Self.releasesPage
        return UpdateInfo(version: latest, url: url)
    }

    /// Compare dotted numeric versions (e.g. "1.2.0" > "1.1.9"). Non-numeric parts count as 0.
    func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
