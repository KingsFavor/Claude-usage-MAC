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
    // Recorded from the token-exchange response at in-app login (display only).
    var accountEmail: String?
    var organizationName: String?
}

enum CredSource { case app, claudeCode }

struct LoadedCreds {
    var creds: OAuthCredentials
    var source: CredSource
}

enum KeychainError: LocalizedError {
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable(let status):
            return "키체인에서 로그인 정보를 읽지 못했습니다 (\(status)).\n키체인 접근을 허용한 뒤 새로고침해 주세요."
        }
    }
}

enum KeychainAuth {
    static let claudeCodeService = "Claude Code-credentials"
    static let appService = "ClaudeUsageMonitor-credentials"

    // MARK: Generic helpers
    /// nil only when the item doesn't exist. Any other failure (keychain locked
    /// after sleep, access prompt denied or timed out, …) throws: it says
    /// nothing about whether the user is logged in, so it must not log them out.
    private static func readItem(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:      return item as? Data
        case errSecItemNotFound: return nil
        default:                 throw KeychainError.unavailable(status)
        }
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
    static func loadAppCreds() throws -> OAuthCredentials? {
        guard let data = try readItem(service: appService) else { return nil }
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
    static func loadClaudeCodeCreds() throws -> OAuthCredentials? {
        guard let data = try readItem(service: claudeCodeService) else { return nil }
        struct Wrapper: Codable { let claudeAiOauth: OAuthCredentials }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: data) { return w.claudeAiOauth }
        return try? JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    private static func saveClaudeCodeCreds(_ creds: OAuthCredentials) {
        var root: [String: Any] = [:]
        if let data = try? readItem(service: claudeCodeService),
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

    // MARK: Explicit sign-out
    // Logging out must stop the app from using ANY credentials — otherwise it
    // silently falls back to Claude Code's token and looks like logout did
    // nothing. Cleared only by an explicit login.
    private static let signedOutKey = "signedOut"

    static var isSignedOut: Bool {
        get { UserDefaults.standard.bool(forKey: signedOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: signedOutKey) }
    }

    // MARK: Unified access (prefer app login, fall back to Claude Code)
    static func load() throws -> LoadedCreds? {
        if isSignedOut { return nil }
        if let c = try loadAppCreds() { return LoadedCreds(creds: c, source: .app) }
        if let c = try loadClaudeCodeCreds() { return LoadedCreds(creds: c, source: .claudeCode) }
        return nil
    }

    static func save(_ creds: OAuthCredentials, source: CredSource) {
        switch source {
        case .app:        saveAppCreds(creds)
        case .claudeCode: saveClaudeCodeCreds(creds)
        }
    }
}
