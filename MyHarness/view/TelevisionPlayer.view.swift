import AVFoundation
import MobileVLCKit
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

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var isMuted = false

    private let mediaPlayer: VLCMediaPlayer
    private var currentURL: URL?

    override init() {
        mediaPlayer = VLCMediaPlayer(options: [
            "--network-caching=1000",
            "--live-caching=1000",
            "--clock-jitter=0",
            "--clock-synchro=0",
        ])
        super.init()
        mediaPlayer.delegate = self
    }

    func attach(to view: UIView) {
        mediaPlayer.drawable = view
    }

    func detach(from view: UIView) {
        guard let drawable = mediaPlayer.drawable as? UIView, drawable === view else { return }
        mediaPlayer.drawable = nil
    }

    func play(url: URL) {
        guard configureAudioSession() else { return }

        if currentURL == url, playbackState == .paused {
            mediaPlayer.play()
            return
        }

        mediaPlayer.stop()
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1000")
        media.addOption(":live-caching=1000")
        mediaPlayer.media = media
        currentURL = url
        playbackState = .opening
        mediaPlayer.play()
    }

    func retry() {
        guard let currentURL else { return }
        play(url: currentURL)
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing, .buffering, .opening:
            mediaPlayer.pause()
        case .paused:
            mediaPlayer.play()
        case .failed:
            retry()
        case .idle:
            guard let currentURL else { return }
            play(url: currentURL)
        }
    }

    func toggleMute() {
        isMuted.toggle()
        mediaPlayer.audio?.isMuted = isMuted
    }

    func stop() {
        mediaPlayer.stop()
        mediaPlayer.media = nil
        currentURL = nil
        playbackState = .idle
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

    private func updatePlaybackState() {
        switch mediaPlayer.state {
        case .stopped, .ended:
            playbackState = .idle
        case .opening:
            playbackState = .opening
        case .buffering, .esAdded:
            playbackState = .buffering
        case .playing:
            playbackState = .playing
        case .paused:
            playbackState = .paused
        case .error:
            playbackState = .failed("映像を再生できませんでした。同じWi-Fiに接続して再試行してください。")
        @unknown default:
            playbackState = .failed("不明な再生エラーが発生しました。")
        }
    }
}

extension TelevisionPlayerController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            self?.updatePlaybackState()
        }
    }
}

struct TelevisionVideoSurface: UIViewRepresentable {
    @ObservedObject var controller: TelevisionPlayerController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        controller.attach(to: view)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Void) {
        // The same controller can move between the inline and full-screen surfaces.
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
