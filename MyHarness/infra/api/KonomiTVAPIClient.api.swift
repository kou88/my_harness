import Foundation

struct KonomiTVAPIClient: Sendable {
    var fetchChannels: @Sendable () async throws -> TelevisionChannelGroups
    var startLiveStream: @Sendable (
        _ channel: TelevisionChannel,
        _ quality: TelevisionStreamQuality
    ) async throws -> TelevisionLiveStreamSession
    var stopLiveStream: @Sendable (_ session: TelevisionLiveStreamSession) async throws -> Void
}

extension KonomiTVAPIClient {
    static func live(serverURL: URL, session: URLSession = .shared) -> KonomiTVAPIClient {
        let endpoints = KonomiTVEndpointBuilder(baseURL: serverURL)

        return KonomiTVAPIClient(
            fetchChannels: {
                let (data, response) = try await session.data(from: endpoints.channelsURL())
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw KonomiTVAPIError.invalidResponse
                }
                guard httpResponse.statusCode == 200 else {
                    throw KonomiTVAPIError.unexpectedStatus(httpResponse.statusCode)
                }
                return try KonomiTVJSONDecoder.make().decode(TelevisionChannelGroups.self, from: data)
            },
            startLiveStream: { channel, quality in
                var request = URLRequest(url: endpoints.liveStreamConnectionURL(for: channel, quality: quality))
                request.httpMethod = "POST"
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw KonomiTVAPIError.invalidResponse
                }
                guard httpResponse.statusCode == 200 else {
                    throw KonomiTVAPIError.unexpectedStatus(httpResponse.statusCode)
                }
                let client = try KonomiTVJSONDecoder.make().decode(
                    TelevisionLiveStreamClientResponse.self,
                    from: data
                )
                return TelevisionLiveStreamSession(
                    clientID: client.clientID,
                    playlistURL: endpoints.liveStreamPlaylistURL(
                        for: channel,
                        quality: quality,
                        clientID: client.clientID
                    ),
                    disconnectURL: endpoints.liveStreamDisconnectURL(
                        for: channel,
                        quality: quality,
                        clientID: client.clientID
                    )
                )
            },
            stopLiveStream: { liveStreamSession in
                var request = URLRequest(url: liveStreamSession.disconnectURL)
                request.httpMethod = "DELETE"
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw KonomiTVAPIError.invalidResponse
                }
                guard httpResponse.statusCode == 204 || httpResponse.statusCode == 422 else {
                    throw KonomiTVAPIError.unexpectedStatus(httpResponse.statusCode)
                }
            }
        )
    }
}

enum KonomiTVAPIError: LocalizedError {
    case invalidResponse
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "テレビサーバーから正しい応答を取得できませんでした。"
        case .unexpectedStatus(let statusCode):
            return "テレビサーバーがエラーを返しました（HTTP \(statusCode)）。"
        }
    }
}
