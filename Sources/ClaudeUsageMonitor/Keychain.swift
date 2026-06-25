import Foundation
import Security

// The app stores its OWN OAuth credentials (from in-app login) under
// "ClaudeUsageMonitor-credentials". If that's absent it falls back to reading
// the token that Claude Code stored under "Claude Code-credentials".

struct OAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?        // epoch milliseconds
    var subscriptionType: String?
    var scopes: [String]?
}

enum CredSource { case app, claudeCode }

struct LoadedCreds {
    var creds: OAuthCredentials
    var source: CredSource
}

enum KeychainAuth {
    static let claudeCodeService = "Claude Code-credentials"
    static let appService = "ClaudeUsageMonitor-credentials"

    // MARK: Generic helpers
    private static func readItem(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func writeItem(service: String, data: Data) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemUpdate(match as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccount as String] = NSUserName()
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    // MARK: App-owned credentials (plain JSON)
    static func loadAppCreds() -> OAuthCredentials? {
        guard let data = readItem(service: appService) else { return nil }
        return try? JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    static func saveAppCreds(_ creds: OAuthCredentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        writeItem(service: appService, data: data)
    }

    static func deleteAppCreds() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService
        ] as CFDictionary)
    }

    // MARK: Claude Code credentials (wrapped JSON, read + refresh write-back)
    static func loadClaudeCodeCreds() -> OAuthCredentials? {
        guard let data = readItem(service: claudeCodeService) else { return nil }
        struct Wrapper: Codable { let claudeAiOauth: OAuthCredentials }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: data) { return w.claudeAiOauth }
        return try? JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    private static func saveClaudeCodeCreds(_ creds: OAuthCredentials) {
        var root: [String: Any] = [:]
        if let data = readItem(service: claudeCodeService),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = creds.accessToken
        if let r = creds.refreshToken { oauth["refreshToken"] = r }
        if let e = creds.expiresAt { oauth["expiresAt"] = e }
        root["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        writeItem(service: claudeCodeService, data: data)
    }

    // MARK: Unified access (prefer app login, fall back to Claude Code)
    static func load() -> LoadedCreds? {
        if let c = loadAppCreds() { return LoadedCreds(creds: c, source: .app) }
        if let c = loadClaudeCodeCreds() { return LoadedCreds(creds: c, source: .claudeCode) }
        return nil
    }

    static func save(_ creds: OAuthCredentials, source: CredSource) {
        switch source {
        case .app:        saveAppCreds(creds)
        case .claudeCode: saveClaudeCodeCreds(creds)
        }
    }
}
