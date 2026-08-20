import Foundation

enum TelevisionBackgroundPlaybackAction: Equatable, Sendable {
    case startPictureInPicture
    case keepPlayingAudio
}

enum TelevisionBackgroundPlaybackPolicy {
    static func action(
        isAppInBackground: Bool,
        hasLiveSession: Bool,
        isActivelyPlaying: Bool,
        isPictureInPicturePossible: Bool
    ) -> TelevisionBackgroundPlaybackAction {
        guard isAppInBackground,
              hasLiveSession,
              isActivelyPlaying,
              isPictureInPicturePossible else {
            return .keepPlayingAudio
        }
        return .startPictureInPicture
    }
}

enum TelevisionPictureInPictureStopAction: Equatable, Sendable {
    case keepPlayback
    case releasePlayback
}

enum TelevisionPictureInPictureStopPolicy {
    static func action(
        isAppInBackground: Bool,
        restoreUserInterfaceRequested: Bool,
        alreadyReleased: Bool,
        isInternalSessionRelease: Bool
    ) -> TelevisionPictureInPictureStopAction {
        isAppInBackground
            && !restoreUserInterfaceRequested
            && !alreadyReleased
            && !isInternalSessionRelease
            ? .releasePlayback
            : .keepPlayback
    }
}

enum TelevisionPauseLeaseAction: Equatable, Sendable {
    case keepCurrentSession
    case releaseSessionKeepingRequest
}

enum TelevisionPauseLeasePolicy {
    static let releaseInterval: TimeInterval = 30

    static func action(pausedDuration: TimeInterval) -> TelevisionPauseLeaseAction {
        pausedDuration < releaseInterval
            ? .keepCurrentSession
            : .releaseSessionKeepingRequest
    }
}

enum TelevisionPlaybackGenerationPolicy {
    static func shouldInstall(resultGeneration: UInt64, currentGeneration: UInt64) -> Bool {
        resultGeneration == currentGeneration
    }
}

actor TelevisionLiveStartOperationGate<Value: Sendable> {
    private var generation: UInt64 = 0
    private var activeTask: Task<Value, Error>?

    func run(
        _ operation: @escaping @Sendable (_ generation: UInt64) async throws -> Value
    ) async throws -> Value {
        let precedingTask = activeTask
        precedingTask?.cancel()
        generation &+= 1
        let operationGeneration = generation
        if let precedingTask {
            _ = try? await precedingTask.value
        }
        try Task.checkCancellation()
        guard generation == operationGeneration else {
            throw CancellationError()
        }
        let task = Task {
            try await operation(operationGeneration)
        }
        activeTask = task
        defer {
            if generation == operationGeneration {
                activeTask = nil
            }
        }
        return try await task.value
    }

    func cancel() {
        generation &+= 1
        activeTask?.cancel()
    }

    func isCurrent(_ operationGeneration: UInt64) -> Bool {
        generation == operationGeneration && activeTask?.isCancelled == false
    }
}

struct TelevisionPendingReleaseQueue<Value: Equatable & Sendable>: Sendable {
    private(set) var values: [Value] = []

    var first: Value? { values.first }

    mutating func remember(_ value: Value) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    mutating func didRelease(_ value: Value) {
        guard values.first == value else { return }
        values.removeFirst()
    }
}

actor TelevisionSerialThrowingOperationGate {
    private var tailTask: Task<Void, Never>?

    func run(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let precedingTask = tailTask
        let operationTask = Task {
            await precedingTask?.value
            try await operation()
        }
        tailTask = Task {
            _ = try? await operationTask.value
        }
        try await operationTask.value
    }
}

enum TelevisionPlaybackStallPolicy {
    static let restartInterval: TimeInterval = 8

    static func shouldRestart(
        stalledDuration: TimeInterval,
        isStillBuffering: Bool,
        resultGeneration: UInt64,
        currentGeneration: UInt64
    ) -> Bool {
        stalledDuration >= restartInterval
            && isStillBuffering
            && TelevisionPlaybackGenerationPolicy.shouldInstall(
                resultGeneration: resultGeneration,
                currentGeneration: currentGeneration
            )
    }
}

enum TelevisionPlaybackWatchdogEvent: Equatable, Sendable {
    case playerItemInstalled
    case waitingToPlay
    case playbackStalled
    case readyToPlay
    case playing
    case explicitlyPaused
    case stopped
}

enum TelevisionPlaybackWatchdogPolicy {
    static func shouldArm(after event: TelevisionPlaybackWatchdogEvent) -> Bool {
        switch event {
        case .playerItemInstalled, .waitingToPlay, .playbackStalled:
            return true
        case .readyToPlay, .playing, .explicitlyPaused, .stopped:
            return false
        }
    }
}

enum TelevisionPlaybackFailureAction: Equatable, Sendable {
    case restartAutomatically
    case deferUntilExplicitResume
}

enum TelevisionPlaybackFailurePolicy {
    static func action(
        shouldPlayWhenReady: Bool,
        isExplicitlyPaused: Bool
    ) -> TelevisionPlaybackFailureAction {
        shouldPlayWhenReady && !isExplicitlyPaused
            ? .restartAutomatically
            : .deferUntilExplicitResume
    }
}

enum TelevisionPlaybackObservationPolicy {
    static func shouldProcessPlayerProgress(shouldPlayWhenReady: Bool) -> Bool {
        shouldPlayWhenReady
    }
}

struct TelevisionNowPlayingMetadata: Equatable, Sendable {
    let channelName: String
    let programTitle: String
    let isLiveStream: Bool
    let playbackRate: Double
}

enum TelevisionRemotePlaybackCommand: CaseIterable, Equatable, Sendable {
    case play
    case pause
    case stop
    case seek
    case skipForward
    case skipBackward
    case next
    case previous
}

enum TelevisionRemoteCommandPolicy {
    static func isEnabled(_ command: TelevisionRemotePlaybackCommand) -> Bool {
        switch command {
        case .play, .pause, .stop:
            return true
        case .seek, .skipForward, .skipBackward, .next, .previous:
            return false
        }
    }
}

enum TelevisionAudioInterruptionAction: Equatable, Sendable {
    case pauseAndScheduleRelease
    case keepCurrentState
    case resumeIfRequested
}

enum TelevisionAudioRouteChangeReason: Equatable, Sendable {
    case oldDeviceUnavailable
    case other
}

enum TelevisionAudioEventPolicy {
    static func interruptionBegan(wasPlaying: Bool) -> TelevisionAudioInterruptionAction {
        wasPlaying ? .pauseAndScheduleRelease : .keepCurrentState
    }

    static func interruptionEnded(
        shouldResume: Bool,
        wasPlayingBeforeInterruption: Bool
    ) -> TelevisionAudioInterruptionAction {
        shouldResume && wasPlayingBeforeInterruption
            ? .resumeIfRequested
            : .keepCurrentState
    }

    static func routeChanged(_ reason: TelevisionAudioRouteChangeReason) -> TelevisionAudioInterruptionAction {
        reason == .oldDeviceUnavailable
            ? .pauseAndScheduleRelease
            : .keepCurrentState
    }
}

enum TelevisionNetworkFailure: Equatable, Sendable {
    case url(URLError.Code)
    case httpStatus(Int)
    case authentication
    case unsafeContract
    case decoding
    case cancelled
    case other
}

enum TelevisionNetworkRetryPolicy {
    static let maximumAttempts = 3

    static func shouldFallbackFromLAN(after failure: TelevisionNetworkFailure) -> Bool {
        guard case .url(let code) = failure else { return false }
        return connectivityCodes.contains(code)
    }

    static func shouldRetryWAN(
        after failure: TelevisionNetworkFailure,
        completedAttempts: Int
    ) -> Bool {
        guard completedAttempts < maximumAttempts else { return false }
        switch failure {
        case .url(let code):
            return connectivityCodes.contains(code)
        case .httpStatus(let statusCode):
            return statusCode == 408
                || statusCode == 425
                || statusCode == 429
                || (500..<600).contains(statusCode)
        case .authentication, .unsafeContract, .decoding, .cancelled, .other:
            return false
        }
    }

    static func backoffNanoseconds(afterCompletedAttempts attempts: Int) -> UInt64 {
        switch attempts {
        case 1:
            return 200_000_000
        case 2:
            return 600_000_000
        default:
            return 0
        }
    }

    private static let connectivityCodes: Set<URLError.Code> = [
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .networkConnectionLost,
        .notConnectedToInternet,
        .timedOut,
    ]
}

enum TelevisionCredentialStoragePolicy {
    static let allowsPersistence = false
}

enum KonomiTVLiveStreamDeletionPolicy {
    private static let missingClientResponse = Data(
        #"{"detail":"Specified client_id was not found"}"#.utf8
    )

    static func isTerminalSuccess(
        statusCode: Int,
        contentType: String,
        responseBody: Data
    ) -> Bool {
        if statusCode == 204 {
            return true
        }
        let mediaType = contentType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return statusCode == 422
            && mediaType == "application/json"
            && responseBody == missingClientResponse
    }
}
