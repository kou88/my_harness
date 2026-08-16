import Foundation
import XCTest
@testable import MyHarnessTelevisionDomain

final class TelevisionModelsTests: XCTestCase {
    func testDecodesAndSortsDisplayableTerrestrialChannels() throws {
        let json = """
        {
          "GR": [
            {
              "id": "channel-3",
              "display_channel_id": "gr031",
              "remocon_id": 3,
              "name": "tvk1",
              "is_display": true,
              "is_watchable": true,
              "program_present": null,
              "program_following": null
            },
            {
              "id": "channel-1",
              "display_channel_id": "gr011",
              "remocon_id": 1,
              "name": "NHK総合1・東京",
              "is_display": true,
              "is_watchable": true,
              "program_present": {
                "id": "program-1",
                "title": "ニュース",
                "description": "番組概要",
                "start_time": "2026-08-16T21:00:00+09:00",
                "end_time": "2026-08-16T22:00:00+09:00"
              },
              "program_following": null
            },
            {
              "id": "hidden",
              "display_channel_id": "gr012",
              "remocon_id": 1,
              "name": "非表示",
              "is_display": false,
              "is_watchable": true,
              "program_present": null,
              "program_following": null
            }
          ]
        }
        """

        let groups = try KonomiTVJSONDecoder.make().decode(
            TelevisionChannelGroups.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(
            groups.displayableTerrestrialChannels.map(\.displayChannelID),
            ["gr011", "gr031"]
        )
        XCTAssertEqual(groups.displayableTerrestrialChannels.first?.currentProgram?.title, "ニュース")
    }

    func testProgramProgressIsClamped() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let program = TelevisionProgram(
            id: "program",
            title: "番組",
            summary: "概要",
            startTime: start,
            endTime: start.addingTimeInterval(100)
        )

        XCTAssertEqual(program.progress(at: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(program.progress(at: start.addingTimeInterval(25)), 0.25)
        XCTAssertEqual(program.progress(at: start.addingTimeInterval(101)), 1)
    }

    func testBuildsKonomiTVURLs() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://192-168-11-54.local.konomi.tv:7000/"))
        let endpoints = KonomiTVEndpointBuilder(baseURL: baseURL)
        let channel = TelevisionChannel(
            id: "NID32736-SID1024",
            displayChannelID: "gr011",
            remoteControlID: 1,
            name: "NHK総合1・東京",
            isDisplay: true,
            isWatchable: true,
            currentProgram: nil,
            followingProgram: nil
        )

        XCTAssertEqual(
            endpoints.channelsURL().absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/channels"
        )
        XCTAssertEqual(
            endpoints.liveStreamURL(for: channel, quality: .high).absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/streams/live/gr011/720p/mpegts"
        )
        XCTAssertEqual(
            endpoints.logoURL(for: channel).absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/channels/NID32736-SID1024/logo"
        )
    }
}
