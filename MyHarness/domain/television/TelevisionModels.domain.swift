import Foundation

enum TelevisionStreamQuality: String, CaseIterable, Identifiable, Sendable {
    case high = "720p"
    case low = "480p"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high:
            return "720p"
        case .low:
            return "480p"
        }
    }
}

enum TelevisionConnectionKind: Equatable, Sendable {
    case localNetwork
    case internet

    var label: String {
        switch self {
        case .localNetwork:
            return "LAN"
        case .internet:
            return "インターネット"
        }
    }
}

struct TelevisionProgram: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let startTime: Date
    let endTime: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary = "description"
        case startTime = "start_time"
        case endTime = "end_time"
    }

    func progress(at date: Date) -> Double {
        let duration = endTime.timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(startTime) / duration, 0), 1)
    }
}

struct TelevisionChannel: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let displayChannelID: String
    let remoteControlID: Int
    let name: String
    let isDisplay: Bool
    let isWatchable: Bool
    let currentProgram: TelevisionProgram?
    let followingProgram: TelevisionProgram?

    enum CodingKeys: String, CodingKey {
        case id
        case displayChannelID = "display_channel_id"
        case remoteControlID = "remocon_id"
        case name
        case isDisplay = "is_display"
        case isWatchable = "is_watchable"
        case currentProgram = "program_present"
        case followingProgram = "program_following"
    }
}

struct TelevisionChannelGroups: Decodable, Equatable, Sendable {
    let terrestrial: [TelevisionChannel]

    enum CodingKeys: String, CodingKey {
        case terrestrial = "GR"
    }

    var displayableTerrestrialChannels: [TelevisionChannel] {
        terrestrial
            .filter { $0.isDisplay && $0.isWatchable }
            .sorted {
                if $0.remoteControlID == $1.remoteControlID {
                    return $0.displayChannelID < $1.displayChannelID
                }
                return $0.remoteControlID < $1.remoteControlID
            }
    }
}

struct TelevisionGatewaySessionCredential: Sendable {
    let sessionID: String
    let sessionToken: String
    let gatewayBaseURL: URL

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionID == rhs.sessionID && lhs.gatewayBaseURL == rhs.gatewayBaseURL
    }
}

extension TelevisionGatewaySessionCredential: Equatable {}

enum TelevisionLiveStreamTransport: Equatable, Sendable {
    case localNetwork
    case gateway(TelevisionGatewaySessionCredential)
}

struct TelevisionLiveStreamSession: Equatable, Sendable {
    let clientID: String
    let playlistURL: URL
    let disconnectURL: URL
    let transport: TelevisionLiveStreamTransport
}

struct TelevisionLiveStreamClientResponse: Decodable, Equatable, Sendable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

struct KonomiTVEndpointBuilder: Sendable {
    let baseURL: URL

    func channelsURL() -> URL {
        baseURL.appendingPathComponent("api/channels")
    }

    func logoURL(for channel: TelevisionChannel) -> URL {
        baseURL
            .appendingPathComponent("api/channels")
            .appendingPathComponent(channel.id)
            .appendingPathComponent("logo")
    }

    func liveStreamConnectionURL(
        for channel: TelevisionChannel,
        quality: TelevisionStreamQuality
    ) -> URL {
        baseURL
            .appendingPathComponent("api/streams/live")
            .appendingPathComponent(channel.displayChannelID)
            .appendingPathComponent(quality.rawValue)
            .appendingPathComponent("ll-hls")
    }

    func liveStreamPlaylistURL(
        for channel: TelevisionChannel,
        quality: TelevisionStreamQuality,
        clientID: String
    ) -> URL {
        liveStreamConnectionURL(for: channel, quality: quality)
            .appendingPathComponent(clientID)
            .appendingPathComponent("primary-audio")
            .appendingPathComponent("playlist.m3u8")
    }

    func liveStreamDisconnectURL(
        for channel: TelevisionChannel,
        quality: TelevisionStreamQuality,
        clientID: String
    ) -> URL {
        liveStreamConnectionURL(for: channel, quality: quality)
            .appendingPathComponent(clientID)
    }
}

struct TelevisionGatewayBootstrapEnvelope: Decodable, Equatable, Sendable {
    let data: TelevisionGatewayBootstrap
}

struct TelevisionGatewayBootstrap: Decodable, Equatable, Sendable {
    let ticket: String
    let gatewayBaseURL: URL
    let expiresAt: Date
}

struct TelevisionGatewaySessionResponse: Decodable, Equatable, Sendable {
    let sessionID: String
    let sessionToken: String
    let playbackBaseURL: URL
    let expiresAt: Date
}

struct TelevisionRemoteEndpointBuilder: Sendable {
    let apiBaseURL: URL

    func bootstrapURL() -> URL {
        apiBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tv")
            .appendingPathComponent("bootstrap")
    }

    static func createSessionURL(gatewayBaseURL: URL) -> URL {
        gatewayBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("sessions")
    }

    static func deleteSessionURL(
        gatewayBaseURL: URL,
        sessionID: String
    ) -> URL {
        createSessionURL(gatewayBaseURL: gatewayBaseURL)
            .appendingPathComponent(sessionID)
    }
}

enum TelevisionRemoteEndpointValidationError: LocalizedError, Equatable {
    case invalidAPIURL
    case invalidGatewayURL
    case invalidPlaybackURL
    case invalidSessionID
    case invalidSessionToken
    case expiredCredential

    var errorDescription: String? {
        switch self {
        case .invalidAPIURL:
            return "テレビ認証APIの接続先が安全ではありません。"
        case .invalidGatewayURL, .invalidPlaybackURL:
            return "テレビゲートウェイから安全でない接続先が返されました。"
        case .invalidSessionID, .invalidSessionToken:
            return "テレビゲートウェイから無効なセッション情報が返されました。"
        case .expiredCredential:
            return "テレビゲートウェイの認証情報が期限切れです。再試行してください。"
        }
    }
}

enum TelevisionRemoteEndpointValidator {
    static func validateAPIBaseURL(_ url: URL) throws {
        guard isSafeHTTPSBaseURL(url) else {
            throw TelevisionRemoteEndpointValidationError.invalidAPIURL
        }
    }

    static func validateBootstrap(
        _ bootstrap: TelevisionGatewayBootstrap,
        expectedGatewayBaseURL: URL,
        now: Date = Date()
    ) throws {
        guard isSafeHTTPSBaseURL(expectedGatewayBaseURL),
              expectedGatewayBaseURL.path.isEmpty || expectedGatewayBaseURL.path == "/",
              isSafeHTTPSBaseURL(bootstrap.gatewayBaseURL),
              bootstrap.gatewayBaseURL.path.isEmpty || bootstrap.gatewayBaseURL.path == "/" else {
            throw TelevisionRemoteEndpointValidationError.invalidGatewayURL
        }
        guard origin(of: bootstrap.gatewayBaseURL) == origin(of: expectedGatewayBaseURL) else {
            throw TelevisionRemoteEndpointValidationError.invalidGatewayURL
        }
        guard bootstrap.expiresAt > now, !bootstrap.ticket.isEmpty else {
            throw TelevisionRemoteEndpointValidationError.expiredCredential
        }
    }

    static func validateSession(
        _ session: TelevisionGatewaySessionResponse,
        gatewayBaseURL: URL,
        now: Date = Date()
    ) throws {
        guard isUUIDv4(session.sessionID) else {
            throw TelevisionRemoteEndpointValidationError.invalidSessionID
        }
        guard isOpaqueSessionToken(session.sessionToken) else {
            throw TelevisionRemoteEndpointValidationError.invalidSessionToken
        }
        guard session.expiresAt > now else {
            throw TelevisionRemoteEndpointValidationError.expiredCredential
        }
        guard isSafePlaybackURL(session.playbackBaseURL, gatewayBaseURL: gatewayBaseURL) else {
            throw TelevisionRemoteEndpointValidationError.invalidPlaybackURL
        }
    }

    private static func isSafeHTTPSBaseURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == "https"
            && components.host != nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
    }

    private static func isSafePlaybackURL(
        _ url: URL,
        gatewayBaseURL: URL
    ) -> Bool {
        guard isSafeHTTPSBaseURL(url), isSafeHTTPSBaseURL(gatewayBaseURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let gatewayComponents = URLComponents(url: gatewayBaseURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        return components.scheme?.lowercased() == gatewayComponents.scheme?.lowercased()
            && components.host?.lowercased() == gatewayComponents.host?.lowercased()
            && effectivePort(components) == effectivePort(gatewayComponents)
            && pathComponents.count == 3
            && pathComponents[0] == "v1"
            && pathComponents[1] == "playback"
            && isOpaqueSessionToken(pathComponents[2])
    }

    private static func effectivePort(_ components: URLComponents) -> Int {
        components.port ?? 443
    }

    private static func origin(of url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return nil
        }
        return "\(scheme)://\(host):\(effectivePort(components))"
    }

    private static func isUUIDv4(_ value: String) -> Bool {
        guard UUID(uuidString: value) != nil, value.count == 36 else { return false }
        let versionIndex = value.index(value.startIndex, offsetBy: 14)
        let variantIndex = value.index(value.startIndex, offsetBy: 19)
        guard value[versionIndex] == "4" else { return false }
        return "89abAB".contains(value[variantIndex])
    }

    private static func isOpaqueSessionToken(_ value: String) -> Bool {
        value.count >= 43
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
    }
}

final class TelevisionAuthenticatedRequestSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum TelevisionGatewaySessionDeletionPolicy {
    static func isTerminalSuccess(statusCode: Int) -> Bool {
        statusCode == 204
            || statusCode == 401
            || statusCode == 404
            || statusCode == 410
    }
}

enum KonomiTVJSONDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ISO 8601形式の日時ではありません。"
            )
        }
        return decoder
    }
}
