import SwiftUI

struct AIInferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState

    var body: some View {
        NavigationStack {
            List {
                if !state.inferenceError.isEmpty {
                    Section { Text(state.inferenceError).foregroundStyle(.red) }
                }
                if state.inferenceHosts.isEmpty && state.inferenceError.isEmpty {
                    Section { Text("推論管理に対応したPCからの同期を待っています。") }
                }
                ForEach(state.inferenceHosts) { host in
                    Section {
                        LabeledContent("PC", value: host.hostName)
                        LabeledContent("状態", value: host.online ? "オンライン" : "オフライン・同期待ち")
                        LabeledContent("設定", value: host.isApplied ? "PCに反映済み" : "PCへの反映待ち")
                        LabeledContent("実行中 / 待機中", value: "\(host.state.active.count) / \(host.state.queued.count)")
                        LabeledContent("予約コンテキスト", value: "\(host.state.reservedContextTokens / 1024)K")
                        if host.state.phase == "loading" { Text("モデルをロードしています").foregroundStyle(.secondary) }
                        if !host.state.error.isEmpty { Text(host.state.error).foregroundStyle(.red) }
                        NavigationLink("実行枠・用途別コンテキスト") {
                            AIInferencePolicyView(state: state, host: host, draft: host.desiredPolicy)
                        }.accessibilityIdentifier("AI.inference.policy")
                    } footer: {
                        Text("チャット・外部API・定期タスク・補助推論で枠を共有します。ツール実行中はGPU枠を使いません。状態は5秒ごとに更新します。")
                    }
                    if !host.state.active.isEmpty { jobs(host.state.active, title: "実行中") }
                    if !host.state.queued.isEmpty { jobs(host.state.queued, title: "順番待ち") }
                }
            }
            .navigationTitle("GPUの実行枠").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .refreshable { await state.refreshInference() }
            .task {
                while !Task.isCancelled {
                    await state.refreshInference()
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
        }
    }

    private func jobs(_ items: [AIInferenceJob], title: String) -> some View {
        Section(title) {
            ForEach(items) { job in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(job.sourceName); Spacer(); Text("\(job.contextLength / 1024)K").monospacedDigit() }
                    Text(job.model).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(job.statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AIInferencePolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState
    let host: AIInferenceHost
    @State var draft: AIInferencePolicy
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                Picker("同時推論数", selection: $draft.maxConcurrentInferences) {
                    ForEach(1...3, id: \.self) { Text("\($0)件").tag($0) }
                }.accessibilityIdentifier("AI.inference.concurrency")
            } footer: { Text("PC全体の上限です。モデルごとの上限と予約容量の両方を満たす推論だけを開始します。") }
            ForEach($draft.models) { $model in
                if let cap = host.state.capabilities.first(where: { $0.model == model.model }) {
                    Section(model.model) {
                        contextPicker("チャットの共通・初期値", value: $model.chatContextLength, cap: cap)
                        contextPicker("外部APIの初期値", value: $model.apiContextLength, cap: cap)
                        contextPicker("定期タスク", value: $model.scheduledContextLength, cap: cap)
                        contextPicker("補助推論", value: $model.auxiliaryContextLength, cap: cap)
                        Text("上限 \(cap.maxConcurrentInferences)推論・合計\(cap.totalContextTokens / 1024)K")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("チャットは共有モードの共通値と新規会話の初期値に適用します。個別会話・APIで明示したコンテキストは優先されます。圧縮などの補助推論は元の会話の容量を引き継ぎます。")
                Text("保存後の新しい推論に適用します。実行中の推論は中断せず、確保済みの容量を維持します。128Kを3件すべて使う長文負荷では待ち時間が増えることがあります。")
                if !state.inferenceError.isEmpty { Text(state.inferenceError).foregroundStyle(.red) }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .disabled(saving)
        .navigationTitle("実行枠の設定").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saving = true
                    Task {
                        let saved = await state.saveInference(hostId: host.hostId, policy: draft)
                        saving = false
                        if saved { dismiss() }
                    }
                }.disabled(saving)
            }
        }
    }

    private func contextPicker(_ title: String, value: Binding<Int>, cap: AIInferenceCapability) -> some View {
        Picker(title, selection: value) {
            ForEach(cap.contextLengths, id: \.self) { Text("\($0 / 1024)K").tag($0) }
        }
    }
}
