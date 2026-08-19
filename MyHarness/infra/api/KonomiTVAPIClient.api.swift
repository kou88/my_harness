import Foundation

struct KonomiTVAPIClient: Sendable {
    var fetchChannels: @Sendable () async throws -> TelevisionChannelGroups
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
