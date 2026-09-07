import Foundation
import XCTest
@testable import MyHarnessHomeControl

private final class MemoryTokenStore: HomeControlTokenPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var token: SharedCognitoToken?
    init(_ token: SharedCognitoToken?) { self.token = token }
    func read() -> SharedCognitoToken? { lock.withLock { token } }
    func save(_ token: SharedCognitoToken) { lock.withLock { self.token = token } }
    func remove() { lock.withLock { token = nil } }
}
private final class TokenProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class HomeControlSessionTests: XCTestCase {
    private let config = ActionInboxConfig(apiBaseURL: URL(string: "https://api.example.com")!, cognitoHostedUIBaseURL: URL(string: "https://auth.example.com")!, cognitoClientID: "test-client", cognitoRedirectURI: "test://auth", cognitoScopes: ["openid"])
    private func token(expired: Bool) -> SharedCognitoToken {
        SharedCognitoToken(accessToken: "old-access", refreshToken: "refresh", idToken: "identity", expiresAt: Date().addingTimeInterval(expired ? -10 : 600))
    }
    private func session(_ store: MemoryTokenStore) -> HomeControlSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TokenProtocol.self]
        return HomeControlSession(store: store, session: URLSession(configuration: configuration))
    }
    func testValidSessionDoesNotContactAuthenticationServer() async throws {
        TokenProtocol.respond = { _ in XCTFail("Valid credentials must not be refreshed"); return (500, Data()) }
        let value = try await session(MemoryTokenStore(token(expired: false))).accessToken(config: config)
        XCTAssertEqual(value, "old-access")
    }
    func testExpiredSessionRefreshesWithoutOpeningAppAndRetainsOAuthRefreshToken() async throws {
        let store = MemoryTokenStore(token(expired: true))
        TokenProtocol.respond = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://auth.example.com/oauth2/token")
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, Data(#"{"access_token":"new-access","expires_in":3600}"#.utf8))
        }
        let value = try await session(store).accessToken(config: config)
        XCTAssertEqual(value, "new-access")
        XCTAssertEqual(store.read()?.refreshToken, "refresh")
        XCTAssertEqual(store.read()?.idToken, "identity")
        XCTAssertGreaterThan(store.read()!.expiresAt.timeIntervalSinceNow, 3500)
    }
    func testSignOutDuringRefreshDoesNotRestoreSession() async {
        let store = MemoryTokenStore(token(expired: true))
        TokenProtocol.respond = { _ in
            store.remove()
            return (200, Data(#"{"access_token":"new-access","expires_in":3600}"#.utf8))
        }
        do { _ = try await session(store).accessToken(config: config); XCTFail("Signed-out operation must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("ログインが変更")) }
        XCTAssertNil(store.read())
    }
    func testRejectedRefreshDoesNotOverwriteCredentialsOrRetry() async {
        let store = MemoryTokenStore(token(expired: true))
        var calls = 0
        TokenProtocol.respond = { _ in calls += 1; return (400, Data()) }
        do { _ = try await session(store).accessToken(config: config); XCTFail("Rejected refresh must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("再ログイン")) }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.read()?.accessToken, "old-access")
    }
    func testMissingSessionDoesNotContactNetwork() async {
        TokenProtocol.respond = { _ in XCTFail("No session must not cause network access"); return (500, Data()) }
        do { _ = try await session(MemoryTokenStore(nil)).accessToken(config: config); XCTFail("Missing session must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("ログイン")) }
    }
}
