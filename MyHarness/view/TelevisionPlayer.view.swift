import AVFoundation
import AVKit
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

    private struct PlaybackRequest: Equatable {
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
    private var playbackGeneration = UUID()
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var pictureInPicturePossibleObservation: NSKeyValueObservation?
    private var pictureInPictureController: AVPictureInPictureController?
    private weak var pictureInPicturePlayerLayer: AVPlayerLayer?
    private var isPictureInPictureStarting = false
    private var currentScenePhase: ScenePhase = .active
    private var backgroundCleanupTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []
    private let onRestoreUserInterface: @MainActor () -> Void

    init(
        apiClient: KonomiTVAPIClient,
        onRestoreUserInterface: @escaping @MainActor () -> Void
    ) {
        self.apiClient = apiClient
        self.onRestoreUserInterface = onRestoreUserInterface
        super.init()

        player.automaticallyWaitsToMinimizeStalling = true
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updatePlaybackStateFromPlayer()
            }
        }
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
        guard configureAudioSession() else { return }

        let request = PlaybackRequest(channel: channel, quality: quality)
        if currentRequest == request, playbackState == .paused {
            player.play()
            return
        }

        currentRequest = request
        let generation = UUID()
        playbackGeneration = generation
        let previousSession = currentSession
        currentSession = nil
        resetPlayerItem()
        playbackState = .opening

        let precedingTask = playbackTask
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await precedingTask?.value

            if let previousSession {
                sessionsPendingRelease.append(previousSession)
            }

            do {
                try await releasePendingSessions()
            } catch {
                guard playbackGeneration == generation else { return }
                playbackState = .failed(
                    "前のチャンネルを解放できませんでした。\n\(error.localizedDescription)"
                )
                return
            }

            guard playbackGeneration == generation else { return }

            do {
                let session = try await apiClient.startLiveStream(channel, quality)
                guard playbackGeneration == generation else {
                    sessionsPendingRelease.append(session)
                    try? await releasePendingSessions()
                    return
                }

                currentSession = session
                installPlayerItem(url: session.playlistURL)
            } catch is CancellationError {
                return
            } catch {
                guard playbackGeneration == generation else { return }
                playbackState = .failed(
                    "映像を開始できませんでした。\n\(error.localizedDescription)"
                )
            }
        }
    }

    func retry() {
        guard let currentRequest else { return }
        play(channel: currentRequest.channel, quality: currentRequest.quality)
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing, .buffering, .opening:
            player.pause()
        case .paused:
            player.play()
        case .failed:
            retry()
        case .idle:
            guard let currentRequest else { return }
            play(channel: currentRequest.channel, quality: currentRequest.quality)
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
        backgroundCleanupTask?.cancel()
        backgroundCleanupTask = nil

        guard phase == .background else { return }

        // canStartPictureInPictureAutomaticallyFromInline を有効にした上で、
        // ホーム画面への遷移時にも明示的に開始を要求する。
        // 手動で一時停止している場合は、ユーザーの意図を尊重して開始しない。
        startPictureInPictureAutomaticallyIfPossible()

        backgroundCleanupTask = Task { [weak self] in
            // PiP の開始コールバックを待ちつつ、開始できなかった配信は
            // チューナーを占有し続けないよう確実に解放する。
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            guard pictureInPictureController?.isPictureInPictureActive != true else { return }
            isPictureInPictureStarting = false
            stop()
        }
    }

    func stopUnlessPictureInPictureIsActive() {
        guard !isPictureInPictureActive, !isPictureInPictureStarting else { return }
        stop()
    }

    func stop() {
        backgroundCleanupTask?.cancel()
        backgroundCleanupTask = nil
        playbackGeneration = UUID()

        let session = currentSession
        currentSession = nil
        currentRequest = nil
        resetPlayerItem()
        playbackState = .idle

        let precedingTask = playbackTask
        playbackTask = Task { [weak self] in
            guard let self else { return }
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
        guard currentSession != nil else { return }
        switch playbackState {
        case .opening, .buffering, .playing:
            break
        case .idle, .paused, .failed:
            return
        }

        guard let pictureInPictureController,
              pictureInPictureController.isPictureInPicturePossible,
              !pictureInPictureController.isPictureInPictureActive,
              !isPictureInPictureStarting else {
            return
        }

        isPictureInPictureStarting = true
        pictureInPictureController.startPictureInPicture()
    }

    private func installPlayerItem(url: URL) {
        removePlayerItemObservers()

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
            [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item else { return }
                switch item.status {
                case .readyToPlay:
                    playbackState = .buffering
                    player.play()
                case .failed:
                    playbackState = .failed(
                        item.error?.localizedDescription
                            ?? "映像を再生できませんでした。同じWi-Fiに接続して再試行してください。"
                    )
                case .unknown:
                    break
                @unknown default:
                    playbackState = .failed("不明な再生エラーが発生しました。")
                }
            }
        }

        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.playbackState = .buffering
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
                    self?.playbackState = .failed(
                        error?.localizedDescription ?? "映像の再生が途中で停止しました。"
                    )
                }
            },
        ]

        player.replaceCurrentItem(with: item)
    }

    private func resetPlayerItem() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removePlayerItemObservers()
    }

    private func removePlayerItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
    }

    private func updatePlaybackStateFromPlayer() {
        guard currentSession != nil else { return }
        switch player.timeControlStatus {
        case .paused:
            if playbackState != .opening, !isFailureState {
                playbackState = .paused
            }
        case .waitingToPlayAtSpecifiedRate:
            if !isFailureState {
                playbackState = .buffering
            }
        case .playing:
            playbackState = .playing
        @unknown default:
            playbackState = .failed("不明な再生エラーが発生しました。")
        }
    }

    private var isFailureState: Bool {
        if case .failed = playbackState { return true }
        return false
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
                self?.isPictureInPicturePossible = controller.isPictureInPicturePossible
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
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isPictureInPictureStarting = false
            self?.isPictureInPictureActive = false
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isPictureInPictureStarting = false
            isPictureInPictureActive = false
            if currentScenePhase == .background {
                stop()
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
            onRestoreUserInterface()
            completionHandler(true)
        }
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
