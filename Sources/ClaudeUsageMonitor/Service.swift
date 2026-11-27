import Foundation

enum UsageServiceError: LocalizedError {
    case noCredentials
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case http(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials:  return "Claude 로그인 정보를 찾을 수 없습니다.\nClaude Code 또는 Claude 앱에 로그인해 주세요."
        case .unauthorized:   return "인증이 만료되었습니다.\nClaude Code에서 다시 로그인해 주세요."
        case .rateLimited:    return "요청이 많아 잠시 제한되었습니다."
        case .http(let code): return "서버 오류 (HTTP \(code))"
        case .network(let m): return "네트워크 오류: \(m)"
        }
    }
}

struct UsageService {
    // Public Claude Code OAuth client id (from the CLI's prod config).
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    /// Returns the usage plus the (possibly refreshed) credentials that fetched it.
    func fetchUsage() async throws -> (usage: UsageResponse, creds: LoadedCreds) {
        var loaded = try loadCreds()
        // The keychain item is shared with Claude Code, which rotates these
        // tokens on its own (and a concurrent refresh rotates them too). So a
        // rejected token/refresh is retried once against a fresh keychain read
        // before it counts as logged out.
        do {
            return try await fetch(with: loaded)
        } catch UsageServiceError.unauthorized {
            let latest = try loadCreds()
            guard latest.creds.accessToken != loaded.creds.accessToken
                    || latest.creds.refreshToken != loaded.creds.refreshToken else {
                throw UsageServiceError.unauthorized
            }
            loaded = latest
            return try await fetch(with: loaded)
        }
    }

    private func loadCreds() throws -> LoadedCreds {
        guard let loaded = try KeychainAuth.load() else { throw UsageServiceError.noCredentials }
        return loaded
    }

    // One pass with the given credentials: refresh first if expired, then on a
    // 401/403 refresh once and retry. Refresh errors propagate as-is, so only a
    // rejected refresh token (not a dropped network after wake) is .unauthorized.
    private func fetch(with loaded: LoadedCreds) async throws -> (usage: UsageResponse, creds: LoadedCreds) {
        var creds = loaded.creds
        if let exp = creds.expiresAt,
           Date(timeIntervalSince1970: exp / 1000.0) <= Date().addingTimeInterval(60) {
            creds = try await refresh(creds)
            KeychainAuth.save(creds, source: loaded.source)
        }
        do {
            let u = try await getUsage(token: creds.accessToken)
            return (u, LoadedCreds(creds: creds, source: loaded.source))
        } catch UsageServiceError.unauthorized {
            let refreshed = try await refresh(creds)
            KeychainAuth.save(refreshed, source: loaded.source)
            let u = try await getUsage(token: refreshed.accessToken)
            return (u, LoadedCreds(creds: refreshed, source: loaded.source))
        }
    }

    private func getUsage(token: String) async throws -> UsageResponse {
        var req = URLRequest(url: Self.usageURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("claude-usage-monitor/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw UsageServiceError.network(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw UsageServiceError.network("잘못된 응답")
        }
        switch http.statusCode {
        case 200:
            do { return try JSONDecoder().decode(UsageResponse.self, from: data) }
            catch { throw UsageServiceError.network("응답 해석 실패") }
        case 401, 403:
            throw UsageServiceError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw UsageServiceError.rateLimited(retryAfter: retryAfter)
        default:
            throw UsageServiceError.http(http.statusCode)
        }
    }

    private func refresh(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        guard let refreshToken = creds.refreshToken else { throw UsageServiceError.unauthorized }
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ])

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw UsageServiceError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw UsageServiceError.network("잘못된 응답")
        }
        switch http.statusCode {
        case 200:
            break
        case 400, 401, 403:  // invalid_grant etc.: the refresh token itself was rejected
            throw UsageServiceError.unauthorized
        case 429:
            let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw UsageServiceError.rateLimited(retryAfter: ra)
        default:
            throw UsageServiceError.http(http.statusCode)
        }
        struct TokenResp: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        guard let t = try? JSONDecoder().decode(TokenResp.self, from: data) else {
            throw UsageServiceError.network("응답 해석 실패")
        }
        var updated = creds
        updated.accessToken = t.access_token
        if let r = t.refresh_token { updated.refreshToken = r }
        if let ei = t.expires_in {
            updated.expiresAt = (Date().timeIntervalSince1970 + ei) * 1000.0
        }
        return updated
    }
}
