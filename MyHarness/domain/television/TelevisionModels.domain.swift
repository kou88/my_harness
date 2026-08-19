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

struct TelevisionLiveStreamSession: Equatable, Sendable {
    let clientID: String
    let playlistURL: URL
    let disconnectURL: URL
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

enum KonomiTVJSONDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
