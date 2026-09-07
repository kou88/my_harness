import Foundation
import Security

// OAuth応答と既存セッションではrefresh/id tokenが省略される場合がある。
struct SharedCognitoToken: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date
}

enum HomeControlError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

protocol HomeControlTokenPersistence: Sendable {
    func read() throws -> SharedCognitoToken?
    func save(_ token: SharedCognitoToken) throws
    func remove() throws
}

struct HomeControlTokenStore: HomeControlTokenPersistence {
    private var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.kou888.myharness.shared-session",
        kSecAttrAccount as String: "cognito",
        kSecAttrAccessGroup as String: "group.com.kou888.myharness"
    ] }
    func read() throws -> SharedCognitoToken? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw HomeControlError.message("ログイン情報を読み取れません。iPhoneのロックを解除してください（\(status)）。")
        }
        return try JSONDecoder().decode(SharedCognitoToken.self, from: data)
    }
    func save(_ token: SharedCognitoToken) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(token),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw HomeControlError.message("ログイン情報の共有に失敗しました（\(status)）。") }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HomeControlError.message("共有ログイン情報を削除できません（\(status)）。")
        }
    }
}

actor HomeControlSession {
    static let shared = HomeControlSession(store: HomeControlTokenStore(), session: URLSession.shared)
    private let store: any HomeControlTokenPersistence
    private let session: URLSession
    init(store: any HomeControlTokenPersistence, session: URLSession) {
        self.store = store
        self.session = session
    }
    func accessToken(config: ActionInboxConfig) async throws -> String {
        guard let token = try store.read() else {
            throw HomeControlError.message("MyHarnessを一度開いてログインしてください。")
        }
        if token.expiresAt.timeIntervalSinceNow > 60 { return token.accessToken }
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw HomeControlError.message("MyHarnessで再ログインしてください。")
        }
        var request = URLRequest(url: config.cognitoHostedUIBaseURL.appendingPathComponent("oauth2/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(["grant_type": "refresh_token", "client_id": config.cognitoClientID, "refresh_token": refreshToken]
            .map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HomeControlError.message("認証サーバーの応答を確認できません。") }
        guard response.statusCode == 200 else {
            throw HomeControlError.message(response.statusCode == 400 || response.statusCode == 401
                ? "MyHarnessで再ログインしてください。" : "ログインを更新できません。時間をおいて再度操作してください。")
        }
        struct Response: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
            let id_token: String?
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        // 更新中のログアウト・アカウント変更があればセッションを復活させない。
        guard let current = try store.read(), current.refreshToken == token.refreshToken else {
            throw HomeControlError.message("ログインが変更されました。もう一度操作してください。")
        }
        if current.accessToken != token.accessToken, current.expiresAt > Date() { return current.accessToken }
        let updated = SharedCognitoToken(accessToken: result.access_token,
            refreshToken: result.refresh_token ?? token.refreshToken,
            idToken: result.id_token ?? token.idToken,
            expiresAt: Date().addingTimeInterval(result.expires_in))
        try store.save(updated)
        return updated.accessToken
    }
}
