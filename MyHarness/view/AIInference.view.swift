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

struct AIChatContextView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState
    let model: AIModel
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView("コンテキスト設定を取得中") }
                else if let host = state.inferenceHosts.first(where: { $0.hostId == model.hostId }),
                        let cap = host.state.capabilities.first(where: { $0.model == model.model }) {
                    AIChatContextEditor(state: state, model: model, host: host, cap: cap, draft: host.desiredPolicy)
                } else {
                    VStack(spacing: 16) {
                        Text(state.inferenceError.isEmpty ? "このPCのコンテキスト設定を取得できません。" : state.inferenceError)
                        Button("再読み込み") { Task { await reload() } }
                    }.padding()
                }
            }
            .navigationTitle("コンテキスト").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .task { await reload() }
        }
    }

    private func reload() async {
        loading = true
        await state.refreshInference()
        loading = false
    }
}

private struct AIChatContextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState
    let model: AIModel
    let host: AIInferenceHost
    let cap: AIInferenceCapability
    @State var draft: AIInferencePolicy
    @State private var saving = false
    @State private var failure = ""

    var body: some View {
        Form {
            Section { Text(model.name); Text(host.hostName).foregroundStyle(.secondary) }
            Section {
                ForEach($draft.models) { $policy in
                    if policy.model == model.model {
                        Picker("チャットのコンテキスト", selection: $policy.chatContextLength) {
                            ForEach(cap.contextLengths, id: \.self) { Text("\($0 / 1024)K").tag($0) }
                        }.pickerStyle(.inline).accessibilityIdentifier("AI.context.length")
                    }
                }
            } footer: {
                Text("共有チャットと新規会話に適用します。実行中の応答はそのまま続き、保存後の送信から切り替わります。")
            }
            if !failure.isEmpty { Section { Text(failure).foregroundStyle(.red) } }
        }
        .disabled(saving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saving = true
                    Task {
                        let saved = await state.saveInference(hostId: host.hostId, policy: draft)
                        saving = false
                        if saved { dismiss() } else { failure = state.inferenceError }
                    }
                }.disabled(saving || draft == host.desiredPolicy).accessibilityIdentifier("AI.context.save")
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

struct AIPowerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var state: AIChatState
    let selectedHostId: String
    @State private var confirmation = false
    @State private var scrolledToHost = false
    @State private var selectedHost = ""
    @State private var selectedName = ""
    @State private var selectedAction = ""
    @State private var showInference = false
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List {
                    if !state.powerError.isEmpty { Section { Text(state.powerError).foregroundStyle(.red) } }
                    if state.powerHosts.isEmpty {
                        Section { Text(state.powerLoaded ? "電源管理に登録されたPCがありません。" : "電源管理に対応したPCを確認しています。").foregroundStyle(.secondary) }
                    }
                    ForEach(state.powerHosts) { host in
                        Section(host.hostName) {
                            LabeledContent("PC", value: host.stateText)
                            LabeledContent("AI", value: host.state == "waiting" || host.state == "stopping" ? "新規受付を停止中" : host.aiReady ? "利用可能" : host.online ? "準備中・要確認" : "未接続")
                            LabeledContent("自宅の中継機", value: host.relayOnline ? "接続中" : "接続不明")
                            if host.online { LabeledContent("実行中 / 待機中", value: "\(host.activeRuns) / \(host.queuedRuns)") }
                            if !host.capturedAt.isEmpty { LabeledContent("最終確認", value: displayDate(host.capturedAt)) }
                            if !host.error.isEmpty { Text(host.error).foregroundStyle(.red) }
                            ForEach(host.blockers, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            if !host.hasActiveOperation {
                                if !host.online {
                                    Button("起動", systemImage: "power") { request(host, action: "wake") }
                                        .disabled(!host.relayOnline || state.powerSubmitting).accessibilityIdentifier("AI.power.wake")
                                } else {
                                    Button("シャットダウン", systemImage: "power", role: .destructive) { request(host, action: "shutdown") }
                                        .disabled(state.powerSubmitting || !host.relayOnline || host.activeRuns + host.queuedRuns > 0 || !host.blockers.isEmpty)
                                        .accessibilityIdentifier("AI.power.shutdown")
                                    Button("作業完了後に停止", systemImage: "clock") { request(host, action: "shutdown_when_idle") }
                                        .disabled(state.powerSubmitting || !host.relayOnline).accessibilityIdentifier("AI.power.wait")
                                }
                            }
                            ForEach(host.operations.filter(\.isActive)) { op in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(op.title + " · " + op.statusText)
                                    Text("確認期限 \(displayDate(op.expiresAt))").font(.caption).foregroundStyle(.secondary)
                                    if op.canCancel { Button("停止予約を取り消す") { Task { await state.cancelPower(op) } }
                                        .disabled(state.powerSubmitting).accessibilityIdentifier("AI.power.cancel") }
                                }
                            }
                            Button("GPUの実行枠・コンテキスト") { showInference = true }
                        }.id(host.id)
                        if !host.operations.isEmpty {
                            Section("操作履歴") {
                                ForEach(host.operations.filter { !$0.isActive }.prefix(5)) { op in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(op.title + " · " + op.statusText)
                                        Text(displayDate(op.updatedAt)).font(.caption).foregroundStyle(.secondary)
                                        if !op.error.isEmpty { Text(op.error).font(.caption).foregroundStyle(.red) }
                                    }
                                }
                            }
                        }
                    }
                }
                .onChange(of: state.powerHosts) { _, _ in if !scrolledToHost && state.powerHosts.contains(where: { $0.id == selectedHostId }) { scroll.scrollTo(selectedHostId, anchor: .top); scrolledToHost = true } }
                .refreshable { await state.refreshPower() }
            }
            .navigationTitle("PC管理").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .confirmationDialog(selectedName + (selectedAction == "wake" ? "を起動しますか？" : "を停止しますか？"), isPresented: $confirmation, titleVisibility: .visible) {
                Button(selectedAction == "wake" ? "起動" : selectedAction == "shutdown" ? "シャットダウン" : "作業完了後に停止", role: selectedAction == "wake" ? nil : .destructive) {
                    Task { await state.operatePower(hostId: selectedHost, action: selectedAction) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(selectedAction == "wake" ? "起動後、AIサービスの準備完了まで確認します。" : "新しい作業の受付を止め、受付済みの作業と結果の保存が終わってから通常シャットダウンします。停止予約は60分で期限切れになります。")
            }
            .sheet(isPresented: $showInference) { AIInferenceView(state: state) }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { await state.refreshPower() }
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await state.refreshPower() } } }
        }
    }
    private func request(_ host: AIPowerHost, action: String) {
        selectedHost = host.id; selectedName = host.hostName; selectedAction = action; confirmation = true
    }
    private func displayDate(_ value: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}
