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
        let clientID = "2ca638d9-7e67-4386-9f7f-3ceec183b595"
        XCTAssertEqual(
            endpoints.liveStreamConnectionURL(for: channel, quality: .high).absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/streams/live/gr011/720p/ll-hls"
        )
        XCTAssertEqual(
            endpoints.liveStreamPlaylistURL(
                for: channel,
                quality: .high,
                clientID: clientID
            ).absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/streams/live/gr011/720p/ll-hls/2ca638d9-7e67-4386-9f7f-3ceec183b595/primary-audio/playlist.m3u8"
        )
        XCTAssertEqual(
            endpoints.liveStreamDisconnectURL(
                for: channel,
                quality: .high,
                clientID: clientID
            ).absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/streams/live/gr011/720p/ll-hls/2ca638d9-7e67-4386-9f7f-3ceec183b595"
        )
        XCTAssertEqual(
            endpoints.logoURL(for: channel).absoluteString,
            "https://192-168-11-54.local.konomi.tv:7000/api/channels/NID32736-SID1024/logo"
        )
    }

    func testDecodesAndValidatesRemoteGatewayContract() throws {
        let json = """
        {
          "data": {
            "ticket": "signed-bootstrap-ticket",
            "gatewayBaseURL": "https://tv.kou88.dev/",
            "expiresAt": "2026-08-20T12:01:00.000Z"
          }
        }
        """
        let envelope = try KonomiTVJSONDecoder.make().decode(
            TelevisionGatewayBootstrapEnvelope.self,
            from: Data(json.utf8)
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z"))

        XCTAssertNoThrow(
            try TelevisionRemoteEndpointValidator.validateBootstrap(
                envelope.data,
                expectedGatewayBaseURL: try XCTUnwrap(URL(string: "https://tv.kou88.dev")),
                now: now
            )
        )

        let gatewaySession = TelevisionGatewaySessionResponse(
            sessionID: "2ca638d9-7e67-4386-9f7f-3ceec183b595",
            sessionToken: String(repeating: "a", count: 43),
            playbackBaseURL: try XCTUnwrap(URL(
                string: "https://tv.kou88.dev/v1/playback/\(String(repeating: "b", count: 43))/"
            )),
            expiresAt: now.addingTimeInterval(3_600)
        )
        XCTAssertNoThrow(try TelevisionRemoteEndpointValidator.validateSession(
            gatewaySession,
            gatewayBaseURL: envelope.data.gatewayBaseURL,
            now: now
        ))
    }

    func testRejectsGatewayPlaybackURLOnAnotherOrigin() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let response = TelevisionGatewaySessionResponse(
            sessionID: "2ca638d9-7e67-4386-9f7f-3ceec183b595",
            sessionToken: String(repeating: "a", count: 43),
            playbackBaseURL: try XCTUnwrap(URL(
                string: "https://attacker.example/v1/playback/\(String(repeating: "b", count: 43))/"
            )),
            expiresAt: now.addingTimeInterval(60)
        )

        XCTAssertThrowsError(try TelevisionRemoteEndpointValidator.validateSession(
            response,
            gatewayBaseURL: try XCTUnwrap(URL(string: "https://tv.kou88.dev/")),
            now: now
        )) { error in
            XCTAssertEqual(
                error as? TelevisionRemoteEndpointValidationError,
                .invalidPlaybackURL
            )
        }
    }

    func testBuildsOnlyFixedRemoteEndpoints() throws {
        let apiBaseURL = try XCTUnwrap(URL(string: "https://api.kou88.dev/"))
        let gatewayBaseURL = try XCTUnwrap(URL(string: "https://tv.kou88.dev/"))
        let endpoints = TelevisionRemoteEndpointBuilder(apiBaseURL: apiBaseURL)

        XCTAssertEqual(
            endpoints.bootstrapURL().absoluteString,
            "https://api.kou88.dev/api/tv/bootstrap"
        )
        XCTAssertEqual(
            TelevisionRemoteEndpointBuilder.createSessionURL(
                gatewayBaseURL: gatewayBaseURL
            ).absoluteString,
            "https://tv.kou88.dev/v1/sessions"
        )
        XCTAssertEqual(
            TelevisionRemoteEndpointBuilder.deleteSessionURL(
                gatewayBaseURL: gatewayBaseURL,
                sessionID: "2ca638d9-7e67-4386-9f7f-3ceec183b595"
            ).absoluteString,
            "https://tv.kou88.dev/v1/sessions/2ca638d9-7e67-4386-9f7f-3ceec183b595"
        )
    }

    func testRejectsInsecureRemoteAPIBaseURL() throws {
        let url = try XCTUnwrap(URL(string: "http://api.kou88.dev/"))

        XCTAssertThrowsError(try TelevisionRemoteEndpointValidator.validateAPIBaseURL(url)) { error in
            XCTAssertEqual(
                error as? TelevisionRemoteEndpointValidationError,
                .invalidAPIURL
            )
        }
    }

    func testRejectsBootstrapGatewayOutsidePinnedOrigin() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let bootstrap = TelevisionGatewayBootstrap(
            ticket: "signed-bootstrap-ticket",
            gatewayBaseURL: try XCTUnwrap(URL(string: "https://attacker.example/")),
            expiresAt: now.addingTimeInterval(60)
        )

        XCTAssertThrowsError(try TelevisionRemoteEndpointValidator.validateBootstrap(
            bootstrap,
            expectedGatewayBaseURL: try XCTUnwrap(URL(string: "https://tv.kou88.dev")),
            now: now
        )) { error in
            XCTAssertEqual(
                error as? TelevisionRemoteEndpointValidationError,
                .invalidGatewayURL
            )
        }
    }

    func testAuthenticatedSessionDelegateRejectsCrossOriginRedirect() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://tv.kou88.dev/v1/sessions"))
        let redirectedURL = try XCTUnwrap(URL(string: "https://attacker.example/collect"))
        let task = URLSession.shared.dataTask(with: originalURL)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: originalURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectedURL.absoluteString]
        ))
        let delegate = TelevisionAuthenticatedRequestSessionDelegate()
        let recorder = RedirectRequestRecorder(initialRequest: URLRequest(url: redirectedURL))

        delegate.urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectedURL)
        ) { request in
            recorder.record(request)
        }

        XCTAssertNil(recorder.request)
        task.cancel()
    }

    func testExpiredGatewayCredentialDoesNotBlockLaterSessions() {
        XCTAssertTrue(TelevisionGatewaySessionDeletionPolicy.isTerminalSuccess(statusCode: 204))
        XCTAssertTrue(TelevisionGatewaySessionDeletionPolicy.isTerminalSuccess(statusCode: 401))
        XCTAssertTrue(TelevisionGatewaySessionDeletionPolicy.isTerminalSuccess(statusCode: 404))
        XCTAssertTrue(TelevisionGatewaySessionDeletionPolicy.isTerminalSuccess(statusCode: 410))
        XCTAssertFalse(TelevisionGatewaySessionDeletionPolicy.isTerminalSuccess(statusCode: 500))
    }
}

private final class RedirectRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    init(initialRequest: URLRequest?) {
        storedRequest = initialRequest
    }

    var request: URLRequest? {
        lock.withLock { storedRequest }
    }

    func record(_ request: URLRequest?) {
        lock.withLock {
            storedRequest = request
        }
    }
}
