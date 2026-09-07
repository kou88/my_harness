import SwiftUI

struct HomeControlView: View {
    @State private var devices: [HomeControlDevice] = []
    @State private var status = "接続を確認しています…"
    @State private var isChecking = false
    var body: some View {
        Form {
            Section("接続") {
                Text(status).font(.subheadline)
                ForEach(devices) { device in
                    Label(device.name, systemImage: device.device == .light ? "lightbulb.fill" : "air.conditioner.horizontal.fill")
                }
                Button("接続を確認") { Task { await checkConnection() } }.disabled(isChecking)
            }
            Section("ホーム画面に追加") {
                Text("ホーム画面を長押しして「編集」→「ウィジェットを追加」→「my harness」を選びます。")
                Label("家電リモコン：ライト＋エアコン", systemImage: "rectangle.split.2x1")
                Label("ライト／エアコン：それぞれ小サイズ", systemImage: "square")
                Text("ボタンはMyHarnessを開かず操作できます。背景をタップするとこの画面が開きます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("エアコンの運転設定") {
                Text("追加したウィジェットを長押しして「ウィジェットを編集」を選びます。")
                Text("前回の設定で運転する場合は「前回設定」を選択。指定して運転する場合はモード・温度・風量をすべて選択してください。")
                Text("設定を変更しただけでは送信しません。「運転」を押すと送信します。「停止」は運転設定なしでも使えます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("赤外線操作のため、表示するのは送信結果です。家電の実際の電源状態ではありません。通信エラー時は自動再送しません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("家電リモコン")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkConnection() }
    }
    @MainActor private func checkConnection() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let client = HomeControlClient(config: try ActionInboxConfig.load())
            devices = try await client.devices()
            status = "接続済み・ウィジェットから操作できます"
        } catch {
            devices = []
            status = error.localizedDescription
        }
    }
}
