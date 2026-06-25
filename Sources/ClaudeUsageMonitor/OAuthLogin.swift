import Foundation
import CryptoKit
import Network
import AppKit

enum OAuthLoginError: LocalizedError {
    case portInUse
    case timeout
    case stateMismatch
    case denied(String)
    case tokenExchange(String)

    var errorDescription: String? {
        switch self {
        case .portInUse:         return "로그인 포트(3118)가 사용 중입니다.\nClaude Code 로그인 창이 열려 있다면 닫고 다시 시도하세요."
        case .timeout:           return "로그인 시간이 초과되었습니다. 다시 시도해 주세요."
        case .stateMismatch:     return "보안 검증(state)에 실패했습니다. 다시 시도해 주세요."
        case .denied(let m):     return "로그인이 거부되었습니다: \(m)"
        case .tokenExchange(let m): return "토큰 교환 실패: \(m)"
        }
    }
}

// Browser-based OAuth (PKCE) login against the Claude account, mirroring the
// flow Claude Code uses. A short-lived loopback server on 127.0.0.1:3118
// captures the redirect.
struct OAuthLogin {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let redirectURI = "http://localhost:3118/callback"
    static let scope = "org:create_api_key user:profile user:inference"
    static let port: UInt16 = 3118

    func run() async throws -> OAuthCredentials {
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafe(32)

        let server = LoopbackServer(port: Self.port, expectedState: state)
        try server.start()
        defer { server.stop() }

        var comps = URLComponents(string: Self.authorizeURL)!
        comps.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        guard let url = comps.url else { throw OAuthLoginError.tokenExchange("authorize URL 생성 실패") }
        await MainActor.run { NSWorkspace.shared.open(url) }

        let code = try await server.waitForCode(timeout: 300)
        return try await Self.exchange(code: code, verifier: verifier)
    }

    static func exchange(code: String, verifier: String) async throws -> OAuthCredentials {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthLoginError.tokenExchange("HTTP \(http?.statusCode ?? -1) \(body.prefix(180))")
        }
        struct T: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double? }
        let t = try JSONDecoder().decode(T.self, from: data)
        var c = OAuthCredentials(accessToken: t.access_token, refreshToken: t.refresh_token,
                                 expiresAt: nil, subscriptionType: nil, scopes: nil)
        if let ei = t.expires_in { c.expiresAt = (Date().timeIntervalSince1970 + ei) * 1000 }
        return c
    }

    // MARK: PKCE helpers
    static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URLEncoded()
    }
    static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// Minimal one-shot loopback HTTP server for the OAuth redirect.
final class LoopbackServer {
    private let port: UInt16
    private let expectedState: String
    private var listener: NWListener?
    private var cont: CheckedContinuation<String, Error>?
    private var finished = false
    private let queue = DispatchQueue(label: "claudeusage.oauth.loopback")

    init(port: UInt16, expectedState: String) {
        self.port = port
        self.expectedState = expectedState
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            throw OAuthLoginError.portInUse
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        l.stateUpdateHandler = { [weak self] st in
            if case .failed = st { self?.queue.async { self?.complete(.failure(OAuthLoginError.portInUse)) } }
        }
        l.start(queue: queue)
    }

    func stop() { queue.async { self.listener?.cancel(); self.listener = nil } }

    func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { c in
            queue.async {
                if self.finished { c.resume(throwing: OAuthLoginError.timeout); return }
                self.cont = c
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.complete(.failure(OAuthLoginError.timeout))
                }
            }
        }
    }

    // Always called on `queue`.
    private func complete(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        listener?.cancel(); listener = nil
        switch result {
        case .success(let s): cont?.resume(returning: s)
        case .failure(let e): cont?.resume(throwing: e)
        }
        cont = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let req = String(data: data, encoding: .utf8),
                  let line = req.split(separator: "\r\n").first else { conn.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { conn.cancel(); return }
            let path = String(parts[1])
            guard path.hasPrefix("/callback") else {
                self.respond(conn, status: "404 Not Found", body: "Not found"); return
            }

            var comps = URLComponents()
            if let q = path.split(separator: "?", maxSplits: 1).dropFirst().first {
                comps.percentEncodedQuery = String(q)
            }
            let items = comps.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

            if let err = value("error") {
                self.respond(conn, status: "200 OK", body: self.html("로그인 실패: \(err)"))
                self.complete(.failure(OAuthLoginError.denied(err)))
                return
            }
            guard let code = value("code"), !code.isEmpty else {
                self.respond(conn, status: "400 Bad Request", body: self.html("인증 코드를 받지 못했습니다."))
                return
            }
            guard value("state") == self.expectedState else {
                self.respond(conn, status: "200 OK", body: self.html("보안 검증에 실패했습니다."))
                self.complete(.failure(OAuthLoginError.stateMismatch))
                return
            }
            // Some flows append "#state" to the code; keep the code part only.
            let clean = code.split(separator: "#").first.map(String.init) ?? code
            self.respond(conn, status: "200 OK",
                         body: self.html("로그인 완료! 이 창을 닫고 메뉴 바로 돌아가세요."))
            self.complete(.success(clean))
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        let payload = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        conn.send(content: payload.data(using: .utf8),
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func html(_ msg: String) -> String {
        """
        <html><head><meta charset='utf-8'><title>Claude Usage</title></head>
        <body style='font-family:-apple-system,system-ui,sans-serif;text-align:center;padding:64px;color:#222'>
        <div style='font-size:40px'>✻</div>
        <h2 style='color:#D9754C;margin:8px 0'>Claude Usage</h2>
        <p style='color:#555'>\(msg)</p></body></html>
        """
    }
}
