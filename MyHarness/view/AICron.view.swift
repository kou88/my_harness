import SwiftUI

struct AICronView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AICronState
    @State private var editor: AICronEditorContext?
    @State private var deleteJob: AICronJob?

    var body: some View {
        List {
            if state.snapshots.count > 1 {
                Section {
                    Picker("実行するPC", selection: Binding(
                        get: { state.selectedHost?.hostId ?? "" },
                        set: { state.selectedHostId = $0 }
                    )) {
                        ForEach(state.snapshots) { host in
                            Text(host.hostName).tag(host.hostId)
                        }
                    }
                }
            }
            if let host = state.selectedHost {
                Section {
                    Label(host.online ? "接続中" : "オフライン", systemImage: host.online ? "checkmark.circle.fill" : "wifi.slash")
                        .foregroundStyle(host.online ? .green : .secondary)
                    Text("Hermesが実行を管理します。アプリを閉じても定期タスクは続きます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !host.suggestions.isEmpty {
                    Section("Hermesからの提案") {
                        ForEach(host.suggestions) { suggestion in
                            AICronSuggestionRow(suggestion: suggestion, isBusy: !state.activeOperationIds.isEmpty) {
                                Task { await state.perform(.acceptSuggestion(suggestionId: suggestion.id)) }
                            } onEdit: {
                                editor = .suggestion(suggestion)
                            } onDismiss: {
                                Task { await state.perform(.dismissSuggestion(suggestionId: suggestion.id)) }
                            }
                        }
                    }
                }
                Section("定期タスク") {
                    if host.jobs.isEmpty {
                        ContentUnavailableView("定期タスクはありません", systemImage: "calendar.badge.clock", description: Text("右上の＋から作成できます。"))
                    } else {
                        ForEach(host.jobs) { job in
                            NavigationLink {
                                AICronJobDetailView(state: state, jobId: job.id, onEdit: { editor = .job($0) }, onDelete: { deleteJob = $0 })
                            } label: {
                                AICronJobRow(job: job)
                            }
                        }
                    }
                }
            } else if state.isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                Section { ContentUnavailableView("まだ同期されていません", systemImage: "desktopcomputer.trianglebadge.exclamationmark") }
            }
            if !state.errorMessage.isEmpty {
                Section { Text(state.errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .navigationTitle("定期タスク")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await state.refresh() }
        .task { await state.refresh() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button { editor = .new } label: { Image(systemName: "plus") }
                    .accessibilityLabel("定期タスクを追加")
                    .disabled(state.selectedHost?.online != true || !state.activeOperationIds.isEmpty)
            }
        }
        .sheet(item: $editor) { context in
            NavigationStack { AICronEditorView(state: state, context: context) }
        }
        .alert("定期タスクを削除しますか？", isPresented: Binding(
            get: { deleteJob != nil }, set: { if !$0 { deleteJob = nil } }
        ), presenting: deleteJob) { job in
            Button("削除", role: .destructive) { Task { await state.perform(.delete(jobId: job.id)); deleteJob = nil } }
            Button("キャンセル", role: .cancel) {}
        } message: { job in Text("「\(job.name)」と実行履歴をHermesから削除します。") }
    }
}

private struct AICronJobRow: View {
    let job: AICronJob
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: job.enabled ? "clock.badge.checkmark" : "pause.circle")
                    .foregroundStyle(job.enabled ? .green : .secondary)
                Text(job.name).font(.headline).lineLimit(2)
            }
            Text(job.scheduleDisplay).font(.subheadline).foregroundStyle(.secondary)
            if !job.nextRunAt.isEmpty { Label(AICronDate.text(job.nextRunAt, prefix: "次回 "), systemImage: "calendar") }
            if !job.lastStatus.isEmpty { Label(AICronStatus.name(job.lastStatus), systemImage: AICronStatus.symbol(job.lastStatus)) }
            if !job.lastError.isEmpty { Text(job.lastError).foregroundStyle(.red).lineLimit(2) }
        }
        .font(.caption)
        .padding(.vertical, 4)
    }
}

private struct AICronSuggestionRow: View {
    let suggestion: AICronSuggestion
    let isBusy: Bool
    let onAccept: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void
    private var isSafe: Bool {
        !suggestion.enabledToolsets.isEmpty && suggestion.enabledToolsets.allSatisfy { $0 == "web" || $0 == "browser" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(suggestion.title).font(.headline)
            if !suggestion.description.isEmpty { Text(suggestion.description).font(.subheadline).foregroundStyle(.secondary) }
            Label(suggestion.schedule, systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
            Text(suggestion.prompt).font(.caption).lineLimit(4)
            HStack {
                Button("登録", action: onAccept).buttonStyle(.borderedProminent).disabled(isBusy || !isSafe)
                Button("編集して登録", action: onEdit).buttonStyle(.bordered).disabled(isBusy)
                Spacer()
                Button("却下", role: .destructive, action: onDismiss).disabled(isBusy)
            }.font(.caption)
            if !isSafe { Text("この提案はそのまま登録できません。安全なツールに編集してください。").font(.caption2).foregroundStyle(.orange) }
        }.padding(.vertical, 5)
    }
}

private struct AICronJobDetailView: View {
    @Bindable var state: AICronState
    let jobId: String
    let onEdit: (AICronJob) -> Void
    let onDelete: (AICronJob) -> Void
    private var job: AICronJob? { state.selectedHost?.jobs.first(where: { $0.id == jobId }) }
    var body: some View {
        List {
            if let job {
                Section {
                    LabeledContent("状態", value: job.enabled ? "有効" : "一時停止")
                    LabeledContent("スケジュール", value: job.scheduleDisplay)
                    if !job.nextRunAt.isEmpty { LabeledContent("次回", value: AICronDate.text(job.nextRunAt)) }
                    if !job.lastRunAt.isEmpty { LabeledContent("前回", value: AICronDate.text(job.lastRunAt)) }
                    LabeledContent("推論量", value: job.reasoningEffort.isEmpty ? "未指定" : job.reasoningEffort)
                    LabeledContent("ツール", value: job.enabledToolsets.joined(separator: ", "))
                }
                Section("指示") { Text(job.prompt).textSelection(.enabled) }
                Section {
                    Button("今すぐ実行", systemImage: "play.fill") { Task { await state.perform(.trigger(jobId: job.id)) } }
                    if job.enabled {
                        Button("一時停止", systemImage: "pause.fill") { Task { await state.perform(.pause(jobId: job.id)) } }
                    } else {
                        Button("再開", systemImage: "arrow.clockwise") { Task { await state.perform(.resume(jobId: job.id)) } }
                    }
                    Button("編集", systemImage: "pencil") { onEdit(job) }
                    Button("削除", systemImage: "trash", role: .destructive) { onDelete(job) }
                }.disabled(!state.activeOperationIds.isEmpty || state.selectedHost?.online != true)
                Section("実行履歴") {
                    if job.runs.isEmpty { Text("実行履歴はありません").foregroundStyle(.secondary) }
                    ForEach(job.runs) { run in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(AICronStatus.name(run.status), systemImage: AICronStatus.symbol(run.status))
                            if run.startedAt > 0 { Text(AICronDate.unix(run.startedAt)).font(.caption).foregroundStyle(.secondary) }
                            if !run.preview.isEmpty { Text(run.preview).font(.caption).lineLimit(4) }
                        }.padding(.vertical, 3)
                    }
                }
            } else {
                ContentUnavailableView("定期タスクが見つかりません", systemImage: "questionmark.folder")
            }
        }.navigationTitle(job?.name ?? "定期タスク").navigationBarTitleDisplayMode(.inline)
    }
}

enum AICronEditorContext: Identifiable {
    case new
    case job(AICronJob)
    case suggestion(AICronSuggestion)
    var id: String {
        switch self { case .new: "new"; case .job(let value): "job-" + value.id; case .suggestion(let value): "suggestion-" + value.id }
    }
}

private struct AICronEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AICronState
    let context: AICronEditorContext
    @State private var name: String
    @State private var prompt: String
    @State private var schedule: String
    @State private var reasoningEffort: String
    @State private var browserEnabled: Bool

    private let efforts = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    private var title: String { if case .job = context { "定期タスクを編集" } else { "定期タスクを追加" } }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        AICronSchedule.isValid(schedule)
    }

    init(state: AICronState, context: AICronEditorContext) {
        self.state = state; self.context = context
        switch context {
        case .new:
            _name = State(initialValue: ""); _prompt = State(initialValue: "")
            _schedule = State(initialValue: "0 9 * * *"); _reasoningEffort = State(initialValue: "medium")
            _browserEnabled = State(initialValue: false)
        case .job(let job):
            _name = State(initialValue: job.name); _prompt = State(initialValue: job.prompt)
            _schedule = State(initialValue: job.schedule); _reasoningEffort = State(initialValue: job.reasoningEffort.isEmpty ? "medium" : job.reasoningEffort)
            _browserEnabled = State(initialValue: job.enabledToolsets.contains("browser"))
        case .suggestion(let suggestion):
            _name = State(initialValue: suggestion.title); _prompt = State(initialValue: suggestion.prompt)
            _schedule = State(initialValue: suggestion.schedule); _reasoningEffort = State(initialValue: "medium")
            _browserEnabled = State(initialValue: suggestion.enabledToolsets.contains("browser"))
        }
    }

    var body: some View {
        Form {
            Section("内容") {
                TextField("名前", text: $name)
                TextField("Hermesへの指示", text: $prompt, axis: .vertical).lineLimit(5...12)
            }
            Section("スケジュール") {
                TextField("例: every 2h / 0 9 * * *", text: $schedule)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button("毎時") { schedule = "every 1h" }
                    Button("毎日9時") { schedule = "0 9 * * *" }
                    Button("平日9時") { schedule = "0 9 * * 1-5" }
                }.buttonStyle(.borderless).font(.caption)
                Text("相対時間は every 30m / every 2h、時刻指定は5項目のcron式を使います。")
                    .font(.caption).foregroundStyle(.secondary)
                if !schedule.isEmpty && !AICronSchedule.isValid(schedule) {
                    Text("every 数字+m/h/d、5項目のcron式、またはISO日時で入力してください。")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section("実行設定") {
                Picker("推論量", selection: $reasoningEffort) { ForEach(efforts, id: \.self) { Text($0).tag($0) } }
                Toggle("ブラウザ操作を許可", isOn: $browserEnabled)
                LabeledContent("常に許可", value: "Web検索")
                Text("端末・ファイル操作、スクリプト実行、外部送信はアプリから作成できません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !state.errorMessage.isEmpty { Section { Text(state.errorMessage).font(.caption).foregroundStyle(.red) } }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { if await save() { dismiss() } } }
                    .disabled(!isValid || !state.activeOperationIds.isEmpty)
            }
        }
    }

    private func save() async -> Bool {
        let spec = AICronJobSpec(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: schedule.trimmingCharacters(in: .whitespacesAndNewlines),
            model: "", reasoningEffort: reasoningEffort,
            enabledToolsets: browserEnabled ? [.web, .browser] : [.web]
        )
        switch context {
        case .new: return await state.create(spec, dismissing: nil)
        case .job(let job): return await state.perform(.update(jobId: job.id, spec: spec))
        case .suggestion(let suggestion): return await state.create(spec, dismissing: suggestion.id)
        }
    }
}

private enum AICronSchedule {
    static func isValid(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^every [1-9][0-9]*[mhd]$"#, options: .regularExpression) != nil { return true }
        if value.split(separator: " ").count == 5 { return true }
        return ISO8601DateFormatter().date(from: value) != nil || value.range(of: #"^[1-9][0-9]*[mhd]$"#, options: .regularExpression) != nil
    }
}

private enum AICronStatus {
    static func name(_ value: String) -> String {
        switch value { case "success", "completed", "succeeded": "完了"; case "running": "実行中"; case "error", "failed": "失敗"; default: value }
    }
    static func symbol(_ value: String) -> String {
        switch value { case "success", "completed", "succeeded": "checkmark.circle"; case "running": "progress.indicator"; case "error", "failed": "exclamationmark.triangle"; default: "circle" }
    }
}

private enum AICronDate {
    private static let input = ISO8601DateFormatter()
    static func text(_ value: String, prefix: String = "") -> String {
        guard let date = input.date(from: value) else { return prefix + value }
        return prefix + date.formatted(date: .abbreviated, time: .shortened)
    }
    static func unix(_ value: Double) -> String {
        Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .shortened)
    }
}
