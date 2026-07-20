import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class CognitoAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private struct StoredToken: Codable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var expiresIn: TimeInterval
        var tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }

    enum AuthError: LocalizedError {
        case missingRedirectScheme
        case browserSessionFailed
        case missingAuthorizationCode
        case stateMismatch
        case missingToken
        case missingIdentityToken
        case tokenRefreshUnavailable
        case tokenEndpointFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingRedirectScheme:
                return "CognitoRedirectURIのschemeが未設定です。"
            case .browserSessionFailed:
                return "Hosted UIを開始できませんでした。"
            case .missingAuthorizationCode:
                return "Hosted UIの戻りURLにcodeがありません。"
            case .stateMismatch:
                return "Hosted UIのstateが一致しません。"
            case .missingToken:
                return "アクセストークンがありません。"
            case .missingIdentityToken:
                return "IDトークンがありません。再ログインしてください。"
            case .tokenRefreshUnavailable:
                return "再ログインが必要です。"
            case .tokenEndpointFailed(let status, let body):
                return "Cognito token endpointが失敗しました: \(status) \(body)"
            }
        }
    }

    private let config: ActionInboxConfig
    private let keychain: KeychainStore
    private let tokenAccount = "action-inbox-token"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var currentSession: ASWebAuthenticationSession?

    init(config: ActionInboxConfig, keychain: KeychainStore = KeychainStore(service: "com.kou888.myharness.action-inbox")) {
        self.config = config
        self.keychain = keychain
    }

    var isSignedIn: Bool {
        (try? loadToken()) != nil
    }

    func accessToken() async throws -> String {
        guard var token = try loadToken() else {
            throw AuthError.missingToken
        }
        if token.expiresAt.timeIntervalSinceNow > 60 {
            return token.accessToken
        }
        token = try await refresh(token: token)
        try saveToken(token)
        return token.accessToken
    }

    func idToken() async throws -> String {
        guard var token = try loadToken() else {
            throw AuthError.missingToken
        }
        if token.expiresAt.timeIntervalSinceNow <= 60 {
            token = try await refresh(token: token)
            try saveToken(token)
        }
        guard let idToken = token.idToken, !idToken.isEmpty else {
            throw AuthError.missingIdentityToken
        }
        return idToken
    }

    func signIn() async throws {
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(byteCount: 24)
        let callbackURL = try await authorizeURL(codeChallenge: challenge, state: state)
        let code = try authorizationCode(from: callbackURL, expectedState: state)
        let token = try await exchangeCode(code, verifier: verifier)
        try saveToken(token)
    }

    func signOut() throws {
        try keychain.removeData(for: tokenAccount)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func authorizeURL(codeChallenge: String, state: String) async throws -> URL {
        guard let scheme = URL(string: config.cognitoRedirectURI)?.scheme else {
            throw AuthError.missingRedirectScheme
        }

        var components = URLComponents(
            url: config.cognitoHostedUIBaseURL.appendingPathComponent("oauth2/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.cognitoClientID),
            URLQueryItem(name: "redirect_uri", value: config.cognitoRedirectURI),
            URLQueryItem(name: "scope", value: config.cognitoScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else {
            throw ActionInboxConfigurationError.invalidURL("CognitoHostedUIBaseURL")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.missingAuthorizationCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            guard session.start() else {
                continuation.resume(throwing: AuthError.browserSessionFailed)
                return
            }
        }
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.missingAuthorizationCode
        }
        let state = components.queryItems?.first { $0.name == "state" }?.value
        guard state == expectedState else {
            throw AuthError.stateMismatch
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingAuthorizationCode
        }
        return code
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> StoredToken {
        try await tokenRequest(fields: [
            "grant_type": "authorization_code",
            "client_id": config.cognitoClientID,
            "code": code,
            "redirect_uri": config.cognitoRedirectURI,
            "code_verifier": verifier
        ], existingToken: nil)
    }

    private func refresh(token: StoredToken) async throws -> StoredToken {
        guard let refreshToken = token.refreshToken else {
            throw AuthError.tokenRefreshUnavailable
        }
        return try await tokenRequest(fields: [
            "grant_type": "refresh_token",
            "client_id": config.cognitoClientID,
            "refresh_token": refreshToken
        ], existingToken: token)
    }

    private func tokenRequest(fields: [String: String], existingToken: StoredToken?) async throws -> StoredToken {
        var request = URLRequest(url: config.cognitoHostedUIBaseURL.appendingPathComponent("oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenEndpointFailed(statusCode, body)
        }

        let token = try decoder.decode(TokenResponse.self, from: data)
        return StoredToken(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? existingToken?.refreshToken,
            idToken: token.idToken ?? existingToken?.idToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn)
        )
    }

    private func loadToken() throws -> StoredToken? {
        guard let data = try keychain.data(for: tokenAccount) else {
            return nil
        }
        return try decoder.decode(StoredToken.self, from: data)
    }

    private func saveToken(_ token: StoredToken) throws {
        try keychain.setData(encoder.encode(token), for: tokenAccount)
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(urlFormEncode(key))=\(urlFormEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    private static func urlFormEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
