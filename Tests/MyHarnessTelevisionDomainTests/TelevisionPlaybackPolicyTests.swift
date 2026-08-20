import Foundation
import XCTest
@testable import MyHarnessTelevisionDomain

final class TelevisionPlaybackPolicyTests: XCTestCase {
    func testPhoneRotationPresentsAndDismissesFullScreenLikeYouTube() {
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .landscape,
                isFullScreen: false,
                hasObservedLandscapeInFullScreen: false,
                isLandscapePresentationSuppressed: false,
                hasSelectedChannel: true,
                isPhone: true
            ),
            .present
        )
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .portrait,
                isFullScreen: true,
                hasObservedLandscapeInFullScreen: true,
                isLandscapePresentationSuppressed: false,
                hasSelectedChannel: true,
                isPhone: true
            ),
            .dismiss
        )
    }

    func testFullScreenButtonIgnoresPortraitUntilLandscapeWasObserved() {
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .portrait,
                isFullScreen: true,
                hasObservedLandscapeInFullScreen: false,
                isLandscapePresentationSuppressed: false,
                hasSelectedChannel: true,
                isPhone: true
            ),
            .none
        )
    }

    func testExplicitExitDoesNotImmediatelyReopenWhilePhoneRemainsLandscape() {
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .landscape,
                isFullScreen: false,
                hasObservedLandscapeInFullScreen: false,
                isLandscapePresentationSuppressed: true,
                hasSelectedChannel: true,
                isPhone: true
            ),
            .none
        )
    }

    func testRotationDoesNotOpenWithoutAChannelOrChangeIPadPresentation() {
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .landscape,
                isFullScreen: false,
                hasObservedLandscapeInFullScreen: false,
                isLandscapePresentationSuppressed: false,
                hasSelectedChannel: false,
                isPhone: true
            ),
            .none
        )
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .landscape,
                isFullScreen: false,
                hasObservedLandscapeInFullScreen: false,
                isLandscapePresentationSuppressed: false,
                hasSelectedChannel: true,
                isPhone: false
            ),
            .none
        )
        XCTAssertEqual(
            TelevisionFullScreenOrientationPolicy.action(
                deviceOrientation: .other,
                isFullScreen: true,
                hasObservedLandscapeInFullScreen: true,
                isLandscapePresentationSuppressed: false,
                hasSelectedChannel: true,
                isPhone: true
            ),
            .none
        )
    }

    func testBackgroundPrefersPiPButNeverReleasesWhenPiPCannotStart() {
        XCTAssertEqual(
            TelevisionBackgroundPlaybackPolicy.action(
                isAppInBackground: true,
                hasLiveSession: true,
                isActivelyPlaying: true,
                isPictureInPicturePossible: true
            ),
            .startPictureInPicture
        )
        XCTAssertEqual(
            TelevisionBackgroundPlaybackPolicy.action(
                isAppInBackground: true,
                hasLiveSession: true,
                isActivelyPlaying: true,
                isPictureInPicturePossible: false
            ),
            .keepPlayingAudio
        )
        XCTAssertEqual(
            TelevisionBackgroundPlaybackPolicy.action(
                isAppInBackground: true,
                hasLiveSession: true,
                isActivelyPlaying: false,
                isPictureInPicturePossible: true
            ),
            .keepPlayingAudio
        )
        XCTAssertEqual(
            TelevisionBackgroundPlaybackPolicy.action(
                isAppInBackground: false,
                hasLiveSession: true,
                isActivelyPlaying: true,
                isPictureInPicturePossible: true
            ),
            .keepPlayingAudio
        )
    }

    func testPauseReleasesAtThirtySecondsButKeepsRequestedChannel() {
        XCTAssertEqual(
            TelevisionPauseLeasePolicy.action(pausedDuration: 29.999),
            .keepCurrentSession
        )
        XCTAssertEqual(
            TelevisionPauseLeasePolicy.action(pausedDuration: 30),
            .releaseSessionKeepingRequest
        )
    }

    func testPiPExplicitBackgroundCloseReleasesOnlyOnceButRestoreKeepsPlayback() {
        XCTAssertEqual(
            TelevisionPictureInPictureStopPolicy.action(
                isAppInBackground: true,
                restoreUserInterfaceRequested: false,
                alreadyReleased: false,
                isInternalSessionRelease: false
            ),
            .releasePlayback
        )
        XCTAssertEqual(
            TelevisionPictureInPictureStopPolicy.action(
                isAppInBackground: true,
                restoreUserInterfaceRequested: true,
                alreadyReleased: false,
                isInternalSessionRelease: false
            ),
            .keepPlayback
        )
        XCTAssertEqual(
            TelevisionPictureInPictureStopPolicy.action(
                isAppInBackground: true,
                restoreUserInterfaceRequested: false,
                alreadyReleased: true,
                isInternalSessionRelease: false
            ),
            .keepPlayback
        )
        XCTAssertEqual(
            TelevisionPictureInPictureStopPolicy.action(
                isAppInBackground: false,
                restoreUserInterfaceRequested: false,
                alreadyReleased: false,
                isInternalSessionRelease: false
            ),
            .keepPlayback
        )
        XCTAssertEqual(
            TelevisionPictureInPictureStopPolicy.action(
                isAppInBackground: true,
                restoreUserInterfaceRequested: false,
                alreadyReleased: false,
                isInternalSessionRelease: true
            ),
            .keepPlayback
        )
    }

    func testOnlyLatestPlaybackGenerationCanInstall() {
        XCTAssertTrue(TelevisionPlaybackGenerationPolicy.shouldInstall(
            resultGeneration: 4,
            currentGeneration: 4
        ))
        XCTAssertFalse(TelevisionPlaybackGenerationPolicy.shouldInstall(
            resultGeneration: 3,
            currentGeneration: 4
        ))
    }

    func testStallWatchdogRestartsOnlyCurrentGenerationAfterEightSeconds() {
        XCTAssertFalse(TelevisionPlaybackStallPolicy.shouldRestart(
            stalledDuration: 7.999,
            isStillBuffering: true,
            resultGeneration: 4,
            currentGeneration: 4
        ))
        XCTAssertFalse(TelevisionPlaybackStallPolicy.shouldRestart(
            stalledDuration: 8,
            isStillBuffering: false,
            resultGeneration: 4,
            currentGeneration: 4
        ))
        XCTAssertFalse(TelevisionPlaybackStallPolicy.shouldRestart(
            stalledDuration: 8,
            isStillBuffering: true,
            resultGeneration: 3,
            currentGeneration: 4
        ))
        XCTAssertTrue(TelevisionPlaybackStallPolicy.shouldRestart(
            stalledDuration: 8,
            isStillBuffering: true,
            resultGeneration: 4,
            currentGeneration: 4
        ))
    }

    func testPlaybackWatchdogCoversInitialUnknownItemAndWaitingPlayback() {
        XCTAssertTrue(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .playerItemInstalled
        ))
        XCTAssertTrue(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .waitingToPlay
        ))
        XCTAssertTrue(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .playbackStalled
        ))
        XCTAssertFalse(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .readyToPlay
        ))
        XCTAssertFalse(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .playing
        ))
        XCTAssertFalse(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .explicitlyPaused
        ))
        XCTAssertFalse(TelevisionPlaybackWatchdogPolicy.shouldArm(
            after: .stopped
        ))
    }

    func testPlaybackFailureNeverRestartsWhileExplicitlyPaused() {
        XCTAssertEqual(
            TelevisionPlaybackFailurePolicy.action(
                shouldPlayWhenReady: false,
                isExplicitlyPaused: true
            ),
            .deferUntilExplicitResume
        )
        XCTAssertEqual(
            TelevisionPlaybackFailurePolicy.action(
                shouldPlayWhenReady: false,
                isExplicitlyPaused: false
            ),
            .deferUntilExplicitResume
        )
        XCTAssertEqual(
            TelevisionPlaybackFailurePolicy.action(
                shouldPlayWhenReady: true,
                isExplicitlyPaused: false
            ),
            .restartAutomatically
        )
        XCTAssertFalse(
            TelevisionPlaybackObservationPolicy.shouldProcessPlayerProgress(
                shouldPlayWhenReady: false
            )
        )
        XCTAssertTrue(
            TelevisionPlaybackObservationPolicy.shouldProcessPlayerProgress(
                shouldPlayWhenReady: true
            )
        )
    }

    func testNowPlayingMetadataContainsDisplayValuesOnly() {
        let metadata = TelevisionNowPlayingMetadata(
            channelName: "NHK総合1・東京",
            programTitle: "ニュース",
            isLiveStream: true,
            playbackRate: 1
        )

        XCTAssertEqual(metadata.channelName, "NHK総合1・東京")
        XCTAssertEqual(metadata.programTitle, "ニュース")
        XCTAssertTrue(metadata.isLiveStream)
        XCTAssertEqual(metadata.playbackRate, 1)
    }

    func testRemoteCommandsEnableOnlyPlayPauseAndStop() {
        XCTAssertTrue(TelevisionRemoteCommandPolicy.isEnabled(.play))
        XCTAssertTrue(TelevisionRemoteCommandPolicy.isEnabled(.pause))
        XCTAssertTrue(TelevisionRemoteCommandPolicy.isEnabled(.stop))
        XCTAssertFalse(TelevisionRemoteCommandPolicy.isEnabled(.seek))
        XCTAssertFalse(TelevisionRemoteCommandPolicy.isEnabled(.skipForward))
        XCTAssertFalse(TelevisionRemoteCommandPolicy.isEnabled(.skipBackward))
        XCTAssertFalse(TelevisionRemoteCommandPolicy.isEnabled(.next))
        XCTAssertFalse(TelevisionRemoteCommandPolicy.isEnabled(.previous))
    }

    func testInterruptionAndRoutePoliciesDoNotInventResumeIntent() {
        XCTAssertEqual(
            TelevisionAudioEventPolicy.interruptionBegan(wasPlaying: true),
            .pauseAndScheduleRelease
        )
        XCTAssertEqual(
            TelevisionAudioEventPolicy.interruptionEnded(
                shouldResume: true,
                wasPlayingBeforeInterruption: true
            ),
            .resumeIfRequested
        )
        XCTAssertEqual(
            TelevisionAudioEventPolicy.interruptionEnded(
                shouldResume: true,
                wasPlayingBeforeInterruption: false
            ),
            .keepCurrentState
        )
        XCTAssertEqual(
            TelevisionAudioEventPolicy.routeChanged(.oldDeviceUnavailable),
            .pauseAndScheduleRelease
        )
        XCTAssertEqual(
            TelevisionAudioEventPolicy.routeChanged(.other),
            .keepCurrentState
        )
    }

    func testOnlyConnectivityFailuresFallbackFromLAN() {
        XCTAssertTrue(TelevisionNetworkRetryPolicy.shouldFallbackFromLAN(
            after: .url(.cannotConnectToHost)
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldFallbackFromLAN(
            after: .url(.cancelled)
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldFallbackFromLAN(
            after: .url(.secureConnectionFailed)
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldFallbackFromLAN(
            after: .httpStatus(422)
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldFallbackFromLAN(
            after: .decoding
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldFallbackFromLAN(
            after: .unsafeContract
        ))
    }

    func testWANTransientRetryIsBoundedToThreeAttempts() {
        XCTAssertTrue(TelevisionNetworkRetryPolicy.shouldRetryWAN(
            after: .url(.networkConnectionLost),
            completedAttempts: 1
        ))
        XCTAssertTrue(TelevisionNetworkRetryPolicy.shouldRetryWAN(
            after: .httpStatus(503),
            completedAttempts: 2
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldRetryWAN(
            after: .httpStatus(503),
            completedAttempts: 3
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldRetryWAN(
            after: .authentication,
            completedAttempts: 1
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldRetryWAN(
            after: .unsafeContract,
            completedAttempts: 1
        ))
        XCTAssertFalse(TelevisionNetworkRetryPolicy.shouldRetryWAN(
            after: .cancelled,
            completedAttempts: 1
        ))
    }

    func testCredentialsAreMemoryOnly() {
        XCTAssertFalse(TelevisionCredentialStoragePolicy.allowsPersistence)
    }

    func testLiveStartGateCancelsTheInFlightTaskBeforeFallbackCanBegin() async throws {
        let gate = TelevisionLiveStartOperationGate<Int>()
        let recorder = TelevisionStartGateRecorder()
        let startTask = Task {
            try await gate.run { _ in
                await recorder.markLocalStart()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    await recorder.markCancellationObserved()
                    throw error
                }
                await recorder.markWANFallback()
                return 1
            }
        }

        await recorder.waitUntilLocalStart()
        await gate.cancel()

        do {
            _ = try await startTask.value
            XCTFail("cancelled start must not return a live session")
        } catch is CancellationError {
            // Expected: URLSession.data(for:)と同じstructured cancellation経路。
        }
        let snapshot = await recorder.snapshot()
        XCTAssertTrue(snapshot.cancellationObserved)
        XCTAssertEqual(snapshot.wanFallbackCount, 0)

        let freshValue = try await gate.run { _ in 2 }
        XCTAssertEqual(freshValue, 2)
    }

    func testFailedAndDuplicateLiveSessionReleasesStayQueuedUntilSuccess() {
        var queue = TelevisionPendingReleaseQueue<String>()
        queue.remember("session-a")
        queue.remember("session-a")

        XCTAssertEqual(queue.values, ["session-a"])
        XCTAssertEqual(queue.first, "session-a")

        // DELETE失敗時はdidReleaseを呼ばないため、次の開始を同じsessionが塞ぐ。
        XCTAssertEqual(queue.first, "session-a")
        queue.didRelease("session-a")
        XCTAssertNil(queue.first)
    }

    func testReleaseGateSerializesRetryAfterAFailedDelete() async throws {
        let gate = TelevisionSerialThrowingOperationGate()
        let recorder = TelevisionReleaseGateRecorder()
        let failedDelete = Task {
            do {
                try await gate.run {
                    await recorder.markFirstStarted()
                    await recorder.waitUntilFirstMayFinish()
                    await recorder.markFirstFinished()
                    throw TelevisionReleaseGateTestError.expectedFailure
                }
                XCTFail("first delete must fail")
            } catch is TelevisionReleaseGateTestError {
                // Expected: queueからpopせず、後続retryへ直列化する。
            }
        }

        await recorder.waitUntilFirstStarted()
        let retryDelete = Task {
            try await gate.run {
                await recorder.markRetryStarted()
            }
        }
        await Task.yield()
        let didRetryStartEarly = await recorder.didRetryStart()
        XCTAssertFalse(didRetryStartEarly)

        await recorder.allowFirstToFinish()
        try await failedDelete.value
        try await retryDelete.value
        let events = await recorder.events()
        XCTAssertEqual(events, ["first-finished", "retry-started"])
    }

    func testLocalDeleteTreatsOnlyExactMissingClientJSONAsTerminal422() {
        XCTAssertTrue(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 204,
            contentType: "",
            responseBody: Data()
        ))
        XCTAssertTrue(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 422,
            contentType: "application/json; charset=utf-8",
            responseBody: Data(#"{"detail":"Specified client_id was not found"}"#.utf8)
        ))
        XCTAssertFalse(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 422,
            contentType: "application/json",
            responseBody: Data(#"{"detail":"Another validation error"}"#.utf8)
        ))
        XCTAssertFalse(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 422,
            contentType: "application/json",
            responseBody: Data(#"{"detail":"Specified client_id was not found","extra":true}"#.utf8)
        ))
        XCTAssertFalse(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 422,
            contentType: "application/json",
            responseBody: Data(
                #"{"detail":"Another validation error","detail":"Specified client_id was not found"}"#.utf8
            )
        ))
        XCTAssertFalse(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 422,
            contentType: "text/plain",
            responseBody: Data(#"{"detail":"Specified client_id was not found"}"#.utf8)
        ))
        XCTAssertFalse(KonomiTVLiveStreamDeletionPolicy.isTerminalSuccess(
            statusCode: 422,
            contentType: "application/json",
            responseBody: Data("not-json".utf8)
        ))
    }
}

private actor TelevisionStartGateRecorder {
    private var localStartObserved = false
    private var cancellationObserved = false
    private var wanFallbackCount = 0

    func markLocalStart() {
        localStartObserved = true
    }

    func waitUntilLocalStart() async {
        while !localStartObserved {
            await Task.yield()
        }
    }

    func markCancellationObserved() {
        cancellationObserved = true
    }

    func markWANFallback() {
        wanFallbackCount += 1
    }

    func snapshot() -> (cancellationObserved: Bool, wanFallbackCount: Int) {
        (cancellationObserved, wanFallbackCount)
    }
}

private enum TelevisionReleaseGateTestError: Error {
    case expectedFailure
}

private actor TelevisionReleaseGateRecorder {
    private var firstStarted = false
    private var firstMayFinish = false
    private var recordedEvents: [String] = []

    func markFirstStarted() {
        firstStarted = true
    }

    func waitUntilFirstStarted() async {
        while !firstStarted {
            await Task.yield()
        }
    }

    func waitUntilFirstMayFinish() async {
        while !firstMayFinish {
            await Task.yield()
        }
    }

    func allowFirstToFinish() {
        firstMayFinish = true
    }

    func markFirstFinished() {
        recordedEvents.append("first-finished")
    }

    func markRetryStarted() {
        recordedEvents.append("retry-started")
    }

    func didRetryStart() -> Bool {
        recordedEvents.contains("retry-started")
    }

    func events() -> [String] {
        recordedEvents
    }
}
