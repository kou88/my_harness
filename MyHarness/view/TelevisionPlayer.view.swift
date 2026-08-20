import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class TelevisionPlayerController: NSObject, ObservableObject {
    enum PlaybackState: Equatable {
        case idle
        case opening
        case buffering
        case playing
        case paused
        case failed(String)
    }

    private struct PlaybackRequest: Equatable, Sendable {
        let channel: TelevisionChannel
        let quality: TelevisionStreamQuality
    }

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var isMuted = false
    @Published private(set) var isPictureInPicturePossible = false
    @Published private(set) var isPictureInPictureActive = false

    private let apiClient: KonomiTVAPIClient
    private let player = AVPlayer()
    private var currentRequest: PlaybackRequest?
    private var currentSession: TelevisionLiveStreamSession?
    private var playbackTask: Task<Void, Never>?
    private var sessionsPendingRelease: [TelevisionLiveStreamSession] = []
    private var playbackGeneration: UInt64 = 0
    private var itemStatusObservation: NSKeyValueObservation?
    private var currentPlayerItemGeneration: UInt64?
    private var timeControlObservation: NSKeyValueObservation?
    private var pictureInPicturePossibleObservation: NSKeyValueObservation?
    private var pictureInPictureController: AVPictureInPictureController?
    private weak var pictureInPicturePlayerLayer: AVPlayerLayer?
    private var isPictureInPictureStarting = false
    private var currentScenePhase: ScenePhase = .active
    private var isRestoringUserInterfaceFromPictureInPicture = false
    private var didReleaseAfterPictureInPictureClose = false
    private var isStoppingPictureInPictureForSessionRelease = false
    private var playerItemNotificationObservers: [NSObjectProtocol] = []
    private var audioNotificationObservers: [NSObjectProtocol] = []
    private var pauseReleaseTask: Task<Void, Never>?
    private var playbackRestartTask: Task<Void, Never>?
    private var stallWatchdogTask: Task<Void, Never>?
    private var logoTask: Task<Void, Never>?
    private var playbackRestartAttempts = 0
    private var requiresFreshPlaybackOnResume = false
    private var pausedAt: Date?
    private var shouldPlayWhenReady = true
    private var wasPlayingBeforeInterruption = false
    private let nowPlayingPublisher = TelevisionNowPlayingPublisher()
    private var remoteCommandController: TelevisionRemoteCommandController!

    init(apiClient: KonomiTVAPIClient) {
        self.apiClient = apiClient
        super.init()

        player.automaticallyWaitsToMinimizeStalling = true
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updatePlaybackStateFromPlayer()
            }
        }
        observeAudioSession()
        remoteCommandController = TelevisionRemoteCommandController(
            play: { [weak self] in self?.resumePlayback() },
            pause: { [weak self] in self?.pausePlayback() },
            stop: { [weak self] in self?.stop() }
        )
    }

    func attach(to view: TelevisionPlayerSurfaceView) {
        let layer = view.playerLayer
        layer.player = player
        layer.videoGravity = .resizeAspect
        guard pictureInPictureController?.isPictureInPictureActive != true else { return }
        guard pictureInPicturePlayerLayer !== layer else { return }
        configurePictureInPicture(for: layer)
    }

    func play(channel: TelevisionChannel, quality: TelevisionStreamQuality) {
        let request = PlaybackRequest(channel: channel, quality: quality)
        if currentRequest == request, currentSession != nil {
            switch playbackState {
            case .paused:
                resumePlayback()
            case .opening, .buffering, .playing:
                break
            case .idle, .failed:
                beginPlayback(request, resetRestartAttempts: true)
            }
            return
        }
        beginPlayback(request, resetRestartAttempts: true)
    }

    private func beginPlayback(
        _ request: PlaybackRequest,
        resetRestartAttempts: Bool
    ) {
        guard configureAudioSession() else {
            let failureState = playbackState
            stop()
            currentRequest = request
            playbackState = failureState
            return
        }
        currentRequest = request

        if resetRestartAttempts {
            playbackRestartAttempts = 0
        }
        pauseReleaseTask?.cancel()
        pauseReleaseTask = nil
        playbackRestartTask?.cancel()
        playbackRestartTask = nil
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        requiresFreshPlaybackOnResume = false
        pausedAt = nil
        shouldPlayWhenReady = true

        let generation = nextPlaybackGeneration()
        let previousSession = currentSession
        currentSession = nil
        resetPlayerItem()
        playbackState = .opening
        nowPlayingPublisher.publish(
            metadata: nowPlayingMetadata(for: request.channel, rate: 0),
            artwork: nil
        )

        let cancellationTask = Task { [apiClient] in
            await apiClient.cancelPendingStarts()
        }

        let precedingTask = playbackTask
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await cancellationTask.value
            await precedingTask?.value

            if let previousSession {
                sessionsPendingRelease.append(previousSession)
            }

            do {
                try await releasePendingSessions()
            } catch {
                guard isCurrent(generation) else { return }
                playbackState = .failed(
                    "前のチャンネルを解放できませんでした。\n\(error.localizedDescription)"
                )
                return
            }

            guard isCurrent(generation) else { return }

            do {
                let session = try await apiClient.startLiveStream(
                    request.channel,
                    request.quality
                )
                guard isCurrent(generation) else {
                    sessionsPendingRelease.append(session)
                    try? await releasePendingSessions()
                    return
                }

                currentSession = session
                installPlayerItem(url: session.playlistURL, generation: generation)
                loadNowPlayingArtwork(for: request.channel, generation: generation)
                startPictureInPictureAutomaticallyIfPossible()
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(generation) else { return }
                playbackState = .failed(
                    "映像を開始できませんでした。\n\(error.localizedDescription)"
                )
            }
        }
    }

    func retry() {
        guard let currentRequest else { return }
        beginPlayback(currentRequest, resetRestartAttempts: true)
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing, .buffering, .opening:
            pausePlayback()
        case .paused:
            resumePlayback()
        case .failed:
            retry()
        case .idle:
            guard let currentRequest else { return }
            play(channel: currentRequest.channel, quality: currentRequest.quality)
        }
    }

    func pausePlayback() {
        wasPlayingBeforeInterruption = false
        switch playbackState {
        case .opening, .buffering, .playing:
            playbackRestartTask?.cancel()
            playbackRestartTask = nil
            stallWatchdogTask?.cancel()
            stallWatchdogTask = nil
            shouldPlayWhenReady = false
            player.pause()
            playbackState = .paused
            pausedAt = Date()
            publishPlaybackRate(0)
            schedulePausedSessionRelease()
        case .idle, .paused, .failed:
            break
        }
    }

    func resumePlayback() {
        guard let currentRequest else { return }
        guard configureAudioSession() else { return }
        if let pausedAt,
           TelevisionPauseLeasePolicy.action(
            pausedDuration: Date().timeIntervalSince(pausedAt)
           ) == .releaseSessionKeepingRequest {
            releaseSessionForExtendedPause()
            beginPlayback(currentRequest, resetRestartAttempts: true)
            return
        }
        pauseReleaseTask?.cancel()
        pauseReleaseTask = nil
        pausedAt = nil
        shouldPlayWhenReady = true
        if case .failed = playbackState {
            beginPlayback(currentRequest, resetRestartAttempts: true)
            return
        }
        if requiresFreshPlaybackOnResume || player.currentItem?.status == .failed {
            beginPlayback(currentRequest, resetRestartAttempts: false)
            return
        }
        if currentSession != nil, player.currentItem != nil {
            playbackState = .buffering
            player.play()
            if let item = player.currentItem,
               let generation = currentPlayerItemGeneration {
                scheduleStallWatchdog(for: item, generation: generation)
            }
            startPictureInPictureAutomaticallyIfPossible()
        } else {
            beginPlayback(currentRequest, resetRestartAttempts: true)
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    func togglePictureInPicture() {
        guard let pictureInPictureController else { return }
        if pictureInPictureController.isPictureInPictureActive {
            pictureInPictureController.stopPictureInPicture()
        } else if pictureInPictureController.isPictureInPicturePossible {
            pictureInPictureController.startPictureInPicture()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        currentScenePhase = phase
        if phase == .active {
            releaseExpiredPausedSessionIfNeeded()
            return
        }
        guard phase == .background else { return }
        startPictureInPictureAutomaticallyIfPossible()
    }

    func handleForegroundTabExit() {
        guard currentScenePhase == .active else { return }
        stop()
    }

    func stop() {
        _ = nextPlaybackGeneration()
        pauseReleaseTask?.cancel()
        pauseReleaseTask = nil
        playbackRestartTask?.cancel()
        playbackRestartTask = nil
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        requiresFreshPlaybackOnResume = false
        pausedAt = nil
        logoTask?.cancel()
        logoTask = nil
        shouldPlayWhenReady = false
        wasPlayingBeforeInterruption = false
        didReleaseAfterPictureInPictureClose = true
        isStoppingPictureInPictureForSessionRelease = false
        if pictureInPictureController?.isPictureInPictureActive == true
            || isPictureInPictureStarting {
            pictureInPictureController?.stopPictureInPicture()
        }

        let session = currentSession
        currentSession = nil
        currentRequest = nil
        resetPlayerItem()
        playbackState = .idle
        nowPlayingPublisher.clear()
        deactivateAudioSession()

        let cancellationTask = Task { [apiClient] in
            await apiClient.cancelPendingStarts()
        }

        let precedingTask = playbackTask
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await cancellationTask.value
            await precedingTask?.value
            if let session {
                sessionsPendingRelease.append(session)
            }
            try? await releasePendingSessions()
            await apiClient.release()
        }
    }

    private func releasePendingSessions() async throws {
        while let session = sessionsPendingRelease.first {
            try await apiClient.stopLiveStream(session)
            sessionsPendingRelease.removeFirst()
        }
    }

    private func startPictureInPictureAutomaticallyIfPossible() {
        let action = TelevisionBackgroundPlaybackPolicy.action(
            isAppInBackground: currentScenePhase == .background,
            hasLiveSession: currentSession != nil,
            isActivelyPlaying: playbackState == .opening
                || playbackState == .buffering
                || playbackState == .playing,
            isPictureInPicturePossible: pictureInPictureController?.isPictureInPicturePossible == true
        )
        guard action == .startPictureInPicture,
              let pictureInPictureController,
              !pictureInPictureController.isPictureInPictureActive,
              !isPictureInPictureStarting else {
            return
        }

        isPictureInPictureStarting = true
        pictureInPictureController.startPictureInPicture()
    }

    private func installPlayerItem(url: URL, generation: UInt64) {
        removePlayerItemObservers()

        let item = AVPlayerItem(url: url)
        currentPlayerItemGeneration = generation
        item.preferredForwardBufferDuration = 2
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
            [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item else { return }
                guard self.isCurrent(generation), self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    cancelStallWatchdog()
                    playbackState = .buffering
                    if shouldPlayWhenReady {
                        player.play()
                        scheduleStallWatchdog(for: item, generation: generation)
                    } else {
                        playbackState = .paused
                    }
                case .failed:
                    handlePlaybackFailure(
                        item.error?.localizedDescription
                            ?? "映像を再生できませんでした。"
                    )
                case .unknown:
                    break
                @unknown default:
                    handlePlaybackFailure("不明な再生エラーが発生しました。")
                }
            }
        }

        let center = NotificationCenter.default
        playerItemNotificationObservers = [
            center.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.player.currentItem === item,
                          self.isCurrent(generation) else { return }
                    self.playbackState = .buffering
                    self.scheduleStallWatchdog(for: item, generation: generation)
                }
            },
            center.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
                        as? Error
                    guard self?.player.currentItem === item else { return }
                    self?.handlePlaybackFailure(
                        error?.localizedDescription ?? "映像の再生が途中で停止しました。"
                    )
                }
            },
        ]

        player.replaceCurrentItem(with: item)
        if shouldPlayWhenReady {
            playbackState = .buffering
            scheduleStallWatchdog(for: item, generation: generation)
        } else {
            playbackState = .paused
            cancelStallWatchdog()
        }
    }

    private func resetPlayerItem() {
        cancelStallWatchdog()
        currentPlayerItemGeneration = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        removePlayerItemObservers()
    }

    private func removePlayerItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        for observer in playerItemNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        playerItemNotificationObservers = []
    }

    private func updatePlaybackStateFromPlayer() {
        guard currentSession != nil else { return }
        guard TelevisionPlaybackObservationPolicy.shouldProcessPlayerProgress(
            shouldPlayWhenReady: shouldPlayWhenReady
        ) else {
            cancelStallWatchdog()
            playbackState = .paused
            publishPlaybackRate(0)
            return
        }
        switch player.timeControlStatus {
        case .paused:
            break
        case .waitingToPlayAtSpecifiedRate:
            if !isFailureState {
                playbackState = .buffering
                if let item = player.currentItem,
                   let generation = currentPlayerItemGeneration {
                    scheduleStallWatchdog(for: item, generation: generation)
                }
            }
        case .playing:
            cancelStallWatchdog()
            playbackState = .playing
            publishPlaybackRate(1)
        @unknown default:
            playbackState = .failed("不明な再生エラーが発生しました。")
        }
    }

    private var isFailureState: Bool {
        if case .failed = playbackState { return true }
        return false
    }

    private func schedulePausedSessionRelease() {
        pauseReleaseTask?.cancel()
        let pausedAt = self.pausedAt ?? Date()
        self.pausedAt = pausedAt
        let elapsed = max(0, Date().timeIntervalSince(pausedAt))
        let remaining = max(0, TelevisionPauseLeasePolicy.releaseInterval - elapsed)
        pauseReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            guard playbackState == .paused else { return }
            releaseSessionForExtendedPause()
        }
    }

    private func releaseExpiredPausedSessionIfNeeded() {
        guard playbackState == .paused, let pausedAt else { return }
        guard TelevisionPauseLeasePolicy.action(
            pausedDuration: Date().timeIntervalSince(pausedAt)
        ) == .releaseSessionKeepingRequest else { return }
        releaseSessionForExtendedPause()
    }

    private func releaseSessionForExtendedPause() {
        guard currentRequest != nil else { return }
        _ = nextPlaybackGeneration()
        pauseReleaseTask?.cancel()
        pauseReleaseTask = nil
        playbackRestartTask?.cancel()
        playbackRestartTask = nil
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        pausedAt = nil

        let session = currentSession
        currentSession = nil
        isStoppingPictureInPictureForSessionRelease =
            pictureInPictureController?.isPictureInPictureActive == true
            || isPictureInPictureStarting
        if isStoppingPictureInPictureForSessionRelease {
            pictureInPictureController?.stopPictureInPicture()
        }
        resetPlayerItem()
        playbackState = .paused
        publishPlaybackRate(0)

        let cancellationTask = Task { [apiClient] in
            await apiClient.cancelPendingStarts()
        }
        let precedingTask = playbackTask
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await cancellationTask.value
            await precedingTask?.value
            if let session {
                sessionsPendingRelease.append(session)
            }
            do {
                try await releasePendingSessions()
            } catch {
                guard currentRequest != nil else { return }
                playbackState = .failed(
                    "一時停止した映像を解放できませんでした。\n\(error.localizedDescription)"
                )
            }
        }
    }

    private func handlePlaybackFailure(_ message: String) {
        guard currentRequest != nil else { return }
        cancelStallWatchdog()
        let isExplicitlyPaused = playbackState == .paused
        guard TelevisionPlaybackFailurePolicy.action(
            shouldPlayWhenReady: shouldPlayWhenReady,
            isExplicitlyPaused: isExplicitlyPaused
        ) == .restartAutomatically else {
            requiresFreshPlaybackOnResume = true
            playbackState = .paused
            publishPlaybackRate(0)
            return
        }
        guard playbackRestartTask == nil else { return }
        requiresFreshPlaybackOnResume = true
        guard playbackRestartAttempts < TelevisionNetworkRetryPolicy.maximumAttempts else {
            playbackState = .failed("映像の再生が停止しました。\n\(message)")
            publishPlaybackRate(0)
            return
        }

        playbackRestartAttempts += 1
        playbackState = .buffering
        publishPlaybackRate(0)
        playbackRestartTask?.cancel()
        let request = currentRequest
        let attempts = playbackRestartAttempts
        playbackRestartTask = Task { [weak self] in
            let nanoseconds = TelevisionNetworkRetryPolicy.backoffNanoseconds(
                afterCompletedAttempts: min(attempts, 2)
            )
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.currentRequest == request,
                  let request else { return }
            beginPlayback(request, resetRestartAttempts: false)
        }
    }

    private func scheduleStallWatchdog(for item: AVPlayerItem, generation: UInt64) {
        cancelStallWatchdog()
        stallWatchdogTask = Task { [weak self, weak item] in
            do {
                try await Task.sleep(for: .seconds(TelevisionPlaybackStallPolicy.restartInterval))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, let item,
                  player.currentItem === item,
                  TelevisionPlaybackStallPolicy.shouldRestart(
                    stalledDuration: TelevisionPlaybackStallPolicy.restartInterval,
                    isStillBuffering: playbackState == .buffering,
                    resultGeneration: generation,
                    currentGeneration: playbackGeneration
                  ) else { return }
            stallWatchdogTask = nil
            handlePlaybackFailure("通信が停止したため映像へ再接続します。")
        }
    }

    private func cancelStallWatchdog() {
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioNotificationObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(notification)
                }
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAudioRouteChange(notification)
                }
            },
        ]
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            let wasPlaying = playbackState == .opening
                || playbackState == .buffering
                || playbackState == .playing
            wasPlayingBeforeInterruption = wasPlaying
            if TelevisionAudioEventPolicy.interruptionBegan(wasPlaying: wasPlaying)
                == .pauseAndScheduleRelease {
                pauseForSystemEvent()
            }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                .contains(.shouldResume)
            let action = TelevisionAudioEventPolicy.interruptionEnded(
                shouldResume: shouldResume,
                wasPlayingBeforeInterruption: wasPlayingBeforeInterruption
            )
            wasPlayingBeforeInterruption = false
            if action == .resumeIfRequested {
                resumePlayback()
            }
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        let policyReason: TelevisionAudioRouteChangeReason = reason == .oldDeviceUnavailable
            ? .oldDeviceUnavailable
            : .other
        if TelevisionAudioEventPolicy.routeChanged(policyReason) == .pauseAndScheduleRelease {
            wasPlayingBeforeInterruption = false
            pauseForSystemEvent()
        }
    }

    private func pauseForSystemEvent() {
        playbackRestartTask?.cancel()
        playbackRestartTask = nil
        cancelStallWatchdog()
        shouldPlayWhenReady = false
        player.pause()
        playbackState = .paused
        if pausedAt == nil {
            pausedAt = Date()
        }
        publishPlaybackRate(0)
        schedulePausedSessionRelease()
    }

    private func loadNowPlayingArtwork(for channel: TelevisionChannel, generation: UInt64) {
        logoTask?.cancel()
        logoTask = Task { [weak self] in
            guard let self else { return }
            let image: UIImage?
            do {
                let data = try await apiClient.fetchChannelLogo(channel)
                image = UIImage(data: data)
            } catch {
                image = nil
            }
            guard !Task.isCancelled, isCurrent(generation), currentRequest?.channel.id == channel.id else {
                return
            }
            nowPlayingPublisher.publish(
                metadata: nowPlayingMetadata(
                    for: channel,
                    rate: playbackState == .playing ? 1 : 0
                ),
                artwork: image
            )
        }
    }

    private func publishPlaybackRate(_ rate: Double) {
        guard let channel = currentRequest?.channel else { return }
        nowPlayingPublisher.updatePlaybackRate(
            metadata: nowPlayingMetadata(for: channel, rate: rate)
        )
    }

    private func nowPlayingMetadata(
        for channel: TelevisionChannel,
        rate: Double
    ) -> TelevisionNowPlayingMetadata {
        TelevisionNowPlayingMetadata(
            channelName: channel.name,
            programTitle: channel.currentProgram?.title ?? "番組情報なし",
            isLiveStream: true,
            playbackRate: rate
        )
    }

    private func nextPlaybackGeneration() -> UInt64 {
        playbackGeneration &+= 1
        return playbackGeneration
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        TelevisionPlaybackGenerationPolicy.shouldInstall(
            resultGeneration: generation,
            currentGeneration: playbackGeneration
        )
    }

    private func configurePictureInPicture(for playerLayer: AVPlayerLayer) {
        // Published 値の更新で SwiftUI が同期的に再描画しても再初期化されないよう、
        // 最初に対象レイヤーを記録する
        pictureInPicturePlayerLayer = playerLayer
        pictureInPicturePossibleObservation?.invalidate()
        pictureInPicturePossibleObservation = nil
        pictureInPictureController = nil
        if isPictureInPicturePossible {
            isPictureInPicturePossible = false
        }

        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else { return }
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPicturePossibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isPictureInPicturePossible = controller.isPictureInPicturePossible
                if controller.isPictureInPicturePossible {
                    startPictureInPictureAutomaticallyIfPossible()
                }
            }
        }
        pictureInPictureController = controller
    }

    private func configureAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            return true
        } catch {
            playbackState = .failed("音声出力を開始できませんでした。\n\(error.localizedDescription)")
            return false
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

extension TelevisionPlayerController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isPictureInPictureStarting = true
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isPictureInPictureStarting = false
            self?.isPictureInPictureActive = true
            self?.didReleaseAfterPictureInPictureClose = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isPictureInPictureStarting = false
            self?.isPictureInPictureActive = false
            // PiP が使えない場合もバックグラウンド音声とチューナーを維持する。
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isPictureInPictureStarting = false
            isPictureInPictureActive = false
            let wasInternalSessionRelease = isStoppingPictureInPictureForSessionRelease
            let action = TelevisionPictureInPictureStopPolicy.action(
                isAppInBackground: currentScenePhase == .background,
                restoreUserInterfaceRequested: isRestoringUserInterfaceFromPictureInPicture,
                alreadyReleased: didReleaseAfterPictureInPictureClose,
                isInternalSessionRelease: isStoppingPictureInPictureForSessionRelease
            )
            if action == .releasePlayback {
                didReleaseAfterPictureInPictureClose = true
                stop()
            }
            isRestoringUserInterfaceFromPictureInPicture = false
            isStoppingPictureInPictureForSessionRelease = false
            if wasInternalSessionRelease {
                startPictureInPictureAutomaticallyIfPossible()
            }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(false)
                return
            }
            guard !didReleaseAfterPictureInPictureClose else {
                completionHandler(false)
                return
            }
            isRestoringUserInterfaceFromPictureInPicture = true
            NotificationCenter.default.post(name: .televisionShouldRestoreUserInterface, object: nil)
            completionHandler(true)
        }
    }
}

extension Notification.Name {
    static let televisionShouldRestoreUserInterface = Notification.Name(
        "TelevisionShouldRestoreUserInterface"
    )
}

@MainActor
private final class TelevisionNowPlayingPublisher {
    private var artwork: MPMediaItemArtwork?

    func publish(metadata: TelevisionNowPlayingMetadata, artwork image: UIImage?) {
        artwork = image.map { image in
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.channelName,
            MPMediaItemPropertyArtist: metadata.programTitle,
            MPNowPlayingInfoPropertyIsLiveStream: metadata.isLiveStream,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.playbackRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyMediaType: MPMediaType.tvShow.rawValue,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = metadata.playbackRate > 0
            ? .playing
            : .paused
    }

    func updatePlaybackRate(metadata: TelevisionNowPlayingMetadata) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = metadata.channelName
        info[MPMediaItemPropertyArtist] = metadata.programTitle
        info[MPNowPlayingInfoPropertyIsLiveStream] = metadata.isLiveStream
        info[MPNowPlayingInfoPropertyPlaybackRate] = metadata.playbackRate
        if artwork == nil {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = metadata.playbackRate > 0
            ? .playing
            : .paused
    }

    func clear() {
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}

@MainActor
private final class TelevisionRemoteCommandController {
    private var targets: [(command: MPRemoteCommand, target: Any)] = []

    init(
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        stop: @escaping @MainActor () -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()
        configure(center.playCommand, isEnabled: true, action: play)
        configure(center.pauseCommand, isEnabled: true, action: pause)
        configure(center.stopCommand, isEnabled: true, action: stop)

        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    deinit {
        for entry in targets {
            entry.command.removeTarget(entry.target)
        }
    }

    private func configure(
        _ command: MPRemoteCommand,
        isEnabled: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        command.isEnabled = isEnabled
        let target = command.addTarget { _ in
            guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else {
                return .commandFailed
            }
            Task { @MainActor in action() }
            return .success
        }
        targets.append((command, target))
    }
}

final class TelevisionPlayerSurfaceView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

struct TelevisionVideoSurface: UIViewRepresentable {
    @ObservedObject var controller: TelevisionPlayerController

    func makeUIView(context: Context) -> TelevisionPlayerSurfaceView {
        let view = TelevisionPlayerSurfaceView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ view: TelevisionPlayerSurfaceView, context: Context) {
        controller.attach(to: view)
    }
}

struct FullScreenTelevisionPlayer: View {
    let channel: TelevisionChannel
    @ObservedObject var controller: TelevisionPlayerController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TelevisionVideoSurface(controller: controller)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text(channel.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button("閉じる", systemImage: "xmark.circle.fill") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
                    .accessibilityLabel("フルスクリーンを閉じる")
                }
                .padding()
                .background(.linearGradient(
                    colors: [.black.opacity(0.72), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                Spacer()

                HStack(spacing: 28) {
                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Image(systemName: controller.playbackState == .paused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(controller.playbackState == .paused ? "再生" : "一時停止")

                    Button {
                        controller.toggleMute()
                    } label: {
                        Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(controller.isMuted ? "ミュート解除" : "ミュート")

                    Button {
                        controller.togglePictureInPicture()
                    } label: {
                        Image(systemName: controller.isPictureInPictureActive
                            ? "pip.exit"
                            : "pip.enter")
                    }
                    .disabled(!controller.isPictureInPicturePossible)
                    .accessibilityLabel(controller.isPictureInPictureActive
                        ? "ピクチャ・イン・ピクチャを終了"
                        : "ピクチャ・イン・ピクチャを開始")
                }
                .font(.title2)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.black.opacity(0.58), in: Capsule())
                .padding(.bottom, 28)
            }
        }
        .statusBarHidden()
    }
}
