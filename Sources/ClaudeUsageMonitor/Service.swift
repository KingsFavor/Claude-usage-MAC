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

    func fetchUsage() async throws -> UsageResponse {
        guard let loaded = KeychainAuth.load() else { throw UsageServiceError.noCredentials }
        var creds = loaded.creds
        let source = loaded.source

        // Proactively refresh if the access token is expired (or about to be).
        if let exp = creds.expiresAt {
            let expDate = Date(timeIntervalSince1970: exp / 1000.0)
            if expDate <= Date().addingTimeInterval(60),
               let refreshed = try? await refresh(creds) {
                creds = refreshed
                KeychainAuth.save(refreshed, source: source)
            }
        }

        do {
            return try await getUsage(token: creds.accessToken)
        } catch UsageServiceError.unauthorized {
            // One reactive refresh attempt on 401/403. A rate-limited refresh
            // must surface as rateLimited (back off) — not as a logout.
            do {
                let refreshed = try await refresh(creds)
                KeychainAuth.save(refreshed, source: source)
                return try await getUsage(token: refreshed.accessToken)
            } catch let UsageServiceError.rateLimited(retryAfter) {
                throw UsageServiceError.rateLimited(retryAfter: retryAfter)
            } catch {
                throw UsageServiceError.unauthorized
            }
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

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        if http?.statusCode == 429 {
            let ra = http?.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw UsageServiceError.rateLimited(retryAfter: ra)
        }
        guard http?.statusCode == 200 else {
            throw UsageServiceError.unauthorized
        }
        struct TokenResp: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let t = try JSONDecoder().decode(TokenResp.self, from: data)
        var updated = creds
        updated.accessToken = t.access_token
        if let r = t.refresh_token { updated.refreshToken = r }
        if let ei = t.expires_in {
            updated.expiresAt = (Date().timeIntervalSince1970 + ei) * 1000.0
        }
        return updated
    }
}
