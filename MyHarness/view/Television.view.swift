import SwiftUI
import UIKit

enum KonomiTVConfiguration {
    static var serverURL: URL {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "KonomiTVBaseURL") as? String,
              let url = URL(string: rawValue),
              url.scheme == "https",
              url.host != nil else {
            fatalError("MyHarnessInfo.plist の KonomiTVBaseURL に有効な HTTPS URL が必要です。")
        }
        return url
    }
}

@MainActor
struct TelevisionView: View {
    private let client: KonomiTVAPIClient

    @Environment(\.scenePhase) private var scenePhase
    @State private var state: TelevisionState
    @StateObject private var playerController: TelevisionPlayerController
    @State private var isFullScreen = false

    init(
        apiClient: KonomiTVAPIClient,
        onRestoreUserInterface: @escaping @MainActor () -> Void = {}
    ) {
        self.client = apiClient
        _state = State(initialValue: TelevisionState(client: apiClient))
        _playerController = StateObject(wrappedValue: TelevisionPlayerController(
            apiClient: apiClient,
            onRestoreUserInterface: onRestoreUserInterface
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            player
            channelContent
        }
        .navigationTitle("テレビ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                qualityPicker
            }
        }
        .task {
            guard state.channels.isEmpty else { return }
            await state.loadChannels()
        }
        .onChange(of: state.quality) { _, _ in
            guard let channel = state.selectedChannel else { return }
            startPlayback(channel)
        }
        .onChange(of: scenePhase) { _, phase in
            playerController.handleScenePhase(phase)
        }
        .onDisappear {
            playerController.stopUnlessPictureInPictureIsActive()
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            if let channel = state.selectedChannel {
                FullScreenTelevisionPlayer(
                    channel: channel,
                    controller: playerController
                )
            }
        }
    }

    private var player: some View {
        ZStack {
            Color.black

            if !isFullScreen {
                TelevisionVideoSurface(controller: playerController)
            }

            playerStatusOverlay

            if state.selectedChannel != nil {
                playerControls
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("テレビ映像")
    }

    @ViewBuilder
    private var playerStatusOverlay: some View {
        switch (state.selectedChannel, playerController.playbackState) {
        case (nil, _):
            VStack(spacing: 10) {
                Image(systemName: "tv")
                    .font(.system(size: 36))
                Text("チャンネルを選択")
                    .font(.headline)
            }
            .foregroundStyle(.white.opacity(0.84))

        case (_, .opening), (_, .buffering):
            ProgressView("受信中…")
                .tint(.white)
                .foregroundStyle(.white)

        case (_, .failed(let message)):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("再試行") {
                    playerController.retry()
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .padding(24)

        case (_, .idle):
            Button {
                guard let channel = state.selectedChannel else { return }
                startPlayback(channel)
            } label: {
                Label("再生", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

        case (_, .paused):
            Button {
                playerController.togglePlayPause()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("再生")

        case (_, .playing):
            EmptyView()
        }
    }

    private var playerControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 18) {
                Text(state.selectedChannel?.name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    playerController.togglePlayPause()
                } label: {
                    Image(systemName: playerController.playbackState == .paused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(playerController.playbackState == .paused ? "再生" : "一時停止")

                Button {
                    playerController.toggleMute()
                } label: {
                    Image(systemName: playerController.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(playerController.isMuted ? "ミュート解除" : "ミュート")

                Button {
                    playerController.togglePictureInPicture()
                } label: {
                    Image(systemName: playerController.isPictureInPictureActive
                        ? "pip.exit"
                        : "pip.enter")
                }
                .disabled(!playerController.isPictureInPicturePossible)
                .accessibilityLabel(playerController.isPictureInPictureActive
                    ? "ピクチャ・イン・ピクチャを終了"
                    : "ピクチャ・イン・ピクチャを開始")

                Button {
                    isFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("フルスクリーン")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.linearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    @ViewBuilder
    private var channelContent: some View {
        if state.channels.isEmpty {
            switch state.loadState {
            case .idle, .loading:
                ProgressView("チャンネルを取得中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("チャンネルを取得できません", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("再試行") {
                        Task { await state.loadChannels() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loaded:
                ContentUnavailableView(
                    "視聴できるチャンネルがありません",
                    systemImage: "tv.slash",
                    description: Text("KonomiTVのチャンネル設定を確認してください。")
                )
            }
        } else {
            List {
                Section("地上波") {
                    ForEach(state.channels) { channel in
                        channelRow(channel)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if let connectionKind = state.connectionKind {
                            Label(
                                "接続: \(connectionKind.label)（LAN優先で自動選択）",
                                systemImage: connectionKind == .localNetwork ? "wifi" : "network"
                            )
                        }
                        Text("再生エンジン: AVPlayer / LL-HLS")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await state.loadChannels()
            }
        }
    }

    private func channelRow(_ channel: TelevisionChannel) -> some View {
        Button {
            state.select(channel)
            startPlayback(channel)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                channelLogo(channel)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(channel.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        if state.selectedChannel?.id == channel.id {
                            Label("視聴中", systemImage: "play.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }

                    if let program = channel.currentProgram {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(program.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                ProgressView(value: program.progress(at: context.date))
                                    .controlSize(.mini)
                                Text(programTimeText(program))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("番組情報なし")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let following = channel.followingProgram {
                        Text("次: \(following.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(channel.name)、\(channel.currentProgram?.title ?? "番組情報なし")")
    }

    private func channelLogo(_ channel: TelevisionChannel) -> some View {
        TelevisionChannelLogo(
            channel: channel,
            connectionKind: state.connectionKind,
            apiClient: client
        )
        .frame(width: 48, height: 36)
        .padding(4)
        .background(.white, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.quaternary, lineWidth: 0.5)
        }
    }

    private var qualityPicker: some View {
        Menu {
            Picker("画質", selection: $state.quality) {
                ForEach(TelevisionStreamQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
        } label: {
            Label(state.quality.label, systemImage: "slider.horizontal.3")
        }
        .accessibilityLabel("画質 \(state.quality.label)")
    }

    private func startPlayback(_ channel: TelevisionChannel) {
        playerController.play(channel: channel, quality: state.quality)
    }

    private func programTimeText(_ program: TelevisionProgram) -> String {
        "\(Self.programTimeFormatter.string(from: program.startTime))–\(Self.programTimeFormatter.string(from: program.endTime))"
    }

    private static let programTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        TelevisionView(apiClient: .live(
            serverURL: URL(string: "https://192-168-11-54.local.konomi.tv:7000/")!
        ))
    }
}

private struct TelevisionChannelLogo: View {
    let channel: TelevisionChannel
    let connectionKind: TelevisionConnectionKind?
    let apiClient: KonomiTVAPIClient

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                channelNumber
            }
        }
        .task(id: "\(channel.id)-\(connectionKind?.label ?? "未接続")") {
            isLoading = true
            defer { isLoading = false }
            do {
                let data = try await apiClient.fetchChannelLogo(channel)
                guard !Task.isCancelled else { return }
                image = UIImage(data: data)
            } catch is CancellationError {
                return
            } catch {
                image = nil
            }
        }
    }

    private var channelNumber: some View {
        Text("\(channel.remoteControlID)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
