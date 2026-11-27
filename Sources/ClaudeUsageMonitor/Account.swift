import Foundation

/// Who the usage numbers belong to — shown in the panel so the user can tell
/// which Claude account (and which credential source) is active.
struct AccountInfo: Equatable {
    var email: String?
    var name: String?
    var organization: String?
    var plan: String?          // e.g. "claude_max" / "max"; feeds planLabel()
    var source: CredSource
}

enum AccountProfile {
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    /// Best effort: the OAuth profile endpoint, else whatever was recorded
    /// locally (token-exchange response for app login, ~/.claude.json for the
    /// Claude Code token). Never throws — account info is decorative.
    static func load(token: String, creds: OAuthCredentials, source: CredSource) async -> AccountInfo {
        var info = local(creds: creds, source: source)
        if let remote = await fetchRemote(token: token) {
            info.email = remote.account?.email ?? remote.account?.email_address ?? info.email
            info.name = remote.account?.display_name ?? remote.account?.full_name ?? info.name
            info.organization = remote.organization?.name ?? info.organization
            info.plan = remote.planHint ?? info.plan
        }
        return info
    }

    private static func local(creds: OAuthCredentials, source: CredSource) -> AccountInfo {
        var info = AccountInfo(email: creds.accountEmail, name: nil,
                               organization: creds.organizationName,
                               plan: creds.subscriptionType, source: source)
        if source == .claudeCode, let oa = claudeCodeAccount() {
            info.email = info.email ?? oa["emailAddress"] as? String
            info.name = oa["displayName"] as? String ?? oa["fullName"] as? String
            info.organization = info.organization ?? oa["organizationName"] as? String
        }
        return info
    }

    /// Claude Code caches the signed-in account in ~/.claude.json ("oauthAccount").
    private static func claudeCodeAccount() -> [String: Any]? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["oauthAccount"] as? [String: Any]
    }

    private struct Profile: Decodable {
        struct Account: Decodable {
            let email: String?
            let email_address: String?
            let full_name: String?
            let display_name: String?
            let has_claude_max: Bool?
            let has_claude_pro: Bool?
        }
        struct Org: Decodable {
            let name: String?
            let organization_type: String?
        }
        let account: Account?
        let organization: Org?

        var planHint: String? {
            if account?.has_claude_max == true { return "max" }
            if account?.has_claude_pro == true { return "pro" }
            return organization?.organization_type
        }
    }

    private static func fetchRemote(token: String) async -> Profile? {
        var req = URLRequest(url: profileURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-usage-monitor/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }
}
