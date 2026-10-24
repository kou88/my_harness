import SwiftUI

enum ExperimentItemKind: String {
    case hypothesis, task, note
}

struct ExperimentItemCreatePresentation: Identifiable {
    let id: UUID
    let session: String
    let kind: ExperimentItemKind
    let tree: ExperimentTree
    let assigneeID: String
}

struct ExperimentItemCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let state: ExperimentState
    let presentation: ExperimentItemCreatePresentation
    let onCreated: () -> Void
    @State private var kind: ExperimentItemKind

    init(state: ExperimentState, presentation: ExperimentItemCreatePresentation, onCreated: @escaping () -> Void) {
        self.state = state; self.presentation = presentation; self.onCreated = onCreated
        _kind = State(initialValue: presentation.kind)
    }
    var body: some View {
        Group {
            switch kind {
            case .hypothesis:
                ExperimentHypothesisCreateView(state: state, presentation: presentation, onCreated: onCreated)
            case .task:
                if presentation.tree.visibleHypotheses.isEmpty {
                    missingParent("先に仮説を追加", symbol: "lightbulb", action: "仮説を追加", kind: .hypothesis)
                } else {
                    ExperimentTaskCreateView(state: state, presentation: presentation, onCreated: onCreated)
                }
            case .note:
                if presentation.tree.visibleTasks.isEmpty {
                    missingParent("先に検証TODOを追加", symbol: "checklist", action: "検証TODOを追加", kind: .task)
                } else {
                    ExperimentNoteCreateView(state: state, presentation: presentation, onCreated: onCreated)
                }
            }
        }
    }
    private func missingParent(_ title: String, symbol: String, action: String, kind: ExperimentItemKind) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } actions: { Button(action) { self.kind = kind } }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
    }
}

private struct ExperimentItemCreateForm<Request: Encodable, Fields: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let identifier: String
    let validationMessage: String
    let buildRequest: () throws -> Request
    let saveRequest: (Request) async throws -> Void
    let onCreated: () -> Void
    @ViewBuilder let fields: () -> Fields
    @State private var phase: ExperimentCreationPhase<Request> = .editing

    var body: some View {
        Form {
            if !phase.message.isEmpty { Text(phase.message).foregroundStyle(.red) }
            fields().disabled(phase.inputsLocked)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }.disabled(phase.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(phase.buttonTitle) { Task { await save() } }
                    .disabled(phase.isSaving || !validationMessage.isEmpty || isSaved)
                    .accessibilityIdentifier("Experiments.\(identifier).save")
            }
        }
        .interactiveDismissDisabled(phase.isSaving)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cognitoDidSignOut"))) { _ in dismiss() }
    }
    private var isSaved: Bool { if case .saved = phase { true } else { false } }
    private func save() async {
        guard !phase.isSaving, !isSaved else { return }
        let request: Request
        do {
            if case .uncertain(let pending, _) = phase { request = pending }
            else { request = try buildRequest() }
        } catch { phase = .rejected(error.localizedDescription); return }
        phase = .saving
        do {
            try await saveRequest(request)
            phase = .saved; onCreated(); dismiss()
        } catch let error as ActionInboxAPIClient.ClientError {
            if case .requestFailed(let status, _) = error, [400, 401, 403, 404, 422].contains(status) {
                phase = .rejected(error.localizedDescription)
            } else { phase = .uncertain(request, error.localizedDescription) }
        } catch { phase = .uncertain(request, error.localizedDescription) }
    }
}

private struct ExperimentHypothesisCreateView: View {
    let state: ExperimentState
    let presentation: ExperimentItemCreatePresentation
    let onCreated: () -> Void
    @State private var draft: ExperimentHypothesisDraft

    init(state: ExperimentState, presentation: ExperimentItemCreatePresentation, onCreated: @escaping () -> Void) {
        self.state = state; self.presentation = presentation; self.onCreated = onCreated
        _draft = State(initialValue: .empty(themeID: presentation.tree.theme.id))
    }
    var body: some View {
        ExperimentItemCreateForm(title: "仮説を追加", identifier: "hypothesis", validationMessage: draft.validationMessage, buildRequest: {
            try ExperimentHypothesisCreateRequest(operationID: presentation.id, draft: draft)
        }, saveRequest: { request in
            _ = try await state.create("hypotheses", request: request, session: presentation.session, as: ExperimentHypothesis.self)
        }, onCreated: onCreated) {
            Section {
                TextField("仮説", text: $draft.statement, axis: .vertical).lineLimit(2...5)
                    .accessibilityIdentifier("Experiments.hypothesis.statement")
                ExperimentStatusPicker(status: $draft.status, choices: [.unverified, .testing])
                ExperimentPriorityPicker(priority: $draft.priority)
            }
            ExperimentInputSection("確認したいこと", text: $draft.question, identifier: "hypothesis.question")
            ExperimentInputSection("成功基準", text: $draft.successCriteria, identifier: "hypothesis.successCriteria")
            ExperimentInputSection("反証基準", text: $draft.falsificationCriteria, identifier: "hypothesis.falsificationCriteria")
            ExperimentInputSection("根拠・背景", text: $draft.background, identifier: "hypothesis.background")
        }
    }
}

private struct ExperimentTaskCreateView: View {
    let state: ExperimentState
    let presentation: ExperimentItemCreatePresentation
    let onCreated: () -> Void
    @State private var draft: ExperimentTaskDraft
    @State private var hasDeadline = false
    @State private var deadline = Date()

    init(state: ExperimentState, presentation: ExperimentItemCreatePresentation, onCreated: @escaping () -> Void) {
        self.state = state; self.presentation = presentation; self.onCreated = onCreated
        let hypotheses = presentation.tree.visibleHypotheses
        _draft = State(initialValue: .empty(hypothesisID: hypotheses.count == 1 ? hypotheses[0].id : "", assigneeID: presentation.assigneeID))
    }
    var body: some View {
        ExperimentItemCreateForm(title: "検証TODOを追加", identifier: "task", validationMessage: draft.validationMessage, buildRequest: {
            var input = draft; input.dueAt = hasDeadline ? deadline : nil
            return try ExperimentTaskCreateRequest(operationID: presentation.id, draft: input)
        }, saveRequest: { request in
            _ = try await state.create("tasks", request: request, session: presentation.session, as: ExperimentTask.self)
        }, onCreated: onCreated) {
            Section {
                Picker("仮説", selection: $draft.hypothesisID) {
                    Text("選択してください").tag("")
                    ForEach(presentation.tree.visibleHypotheses) { Text($0.statement).tag($0.id) }
                }.pickerStyle(.navigationLink).accessibilityIdentifier("Experiments.task.hypothesis")
                TextField("タイトル", text: $draft.title, axis: .vertical).lineLimit(1...3)
                    .accessibilityIdentifier("Experiments.task.title")
                ExperimentStatusPicker(status: $draft.status, choices: [.pending, .inProgress, .paused])
                ExperimentPriorityPicker(priority: $draft.priority)
            }
            ExperimentInputSection("検証方法", text: $draft.method, identifier: "task.method")
            ExperimentInputSection("成果物・測定項目", text: $draft.expectedOutcome, identifier: "task.expectedOutcome")
            Section {
                Toggle("期限を設定", isOn: $hasDeadline)
                if hasDeadline { DatePicker("期限", selection: $deadline) }
            }
        }
    }
}

private struct ExperimentNoteCreateView: View {
    let state: ExperimentState
    let presentation: ExperimentItemCreatePresentation
    let onCreated: () -> Void
    @State private var draft: ExperimentNoteDraft

    init(state: ExperimentState, presentation: ExperimentItemCreatePresentation, onCreated: @escaping () -> Void) {
        self.state = state; self.presentation = presentation; self.onCreated = onCreated
        let tasks = presentation.tree.visibleTasks
        _draft = State(initialValue: .empty(taskID: tasks.count == 1 ? tasks[0].id : "", observedAt: Date()))
    }
    var body: some View {
        ExperimentItemCreateForm(title: "結果ノートを追加", identifier: "note", validationMessage: draft.validationMessage, buildRequest: {
            try ExperimentNoteCreateRequest(operationID: presentation.id, draft: draft)
        }, saveRequest: { request in
            _ = try await state.create("notes", request: request, session: presentation.session, as: ExperimentNote.self)
        }, onCreated: onCreated) {
            Section {
                Picker("検証TODO", selection: $draft.taskID) {
                    Text("選択してください").tag("")
                    ForEach(presentation.tree.visibleTasks) { Text($0.title).tag($0.id) }
                }.pickerStyle(.navigationLink).accessibilityIdentifier("Experiments.note.task")
                TextField("タイトル", text: $draft.title, axis: .vertical).lineLimit(1...3)
                    .accessibilityIdentifier("Experiments.note.title")
                DatePicker("観測日時", selection: $draft.observedAt)
            }
            ExperimentInputSection("観測した事実", text: $draft.facts, identifier: "note.facts")
            ExperimentInputSection("解釈・考察", text: $draft.interpretation, identifier: "note.interpretation")
            Section("参照元") {
                ForEach($draft.sources) { $source in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("名前", text: $source.label)
                        TextField("https://", text: $source.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }.onDelete { draft.sources.remove(atOffsets: $0) }
                Button("参照元を追加", systemImage: "plus") { draft.sources.append(ExperimentSourceDraft(id: UUID(), label: "", url: "")) }
                    .disabled(draft.sources.count >= 100)
            }
            ExperimentInputSection("判明したこと", text: $draft.findings, identifier: "note.findings")
            ExperimentInputSection("未解決事項", text: $draft.unresolved, identifier: "note.unresolved")
            ExperimentInputSection("次の検証候補", text: $draft.nextCandidates, identifier: "note.nextCandidates")
        }
    }
}

private struct ExperimentInputSection: View {
    let title: String
    @Binding var text: String
    let identifier: String
    init(_ title: String, text: Binding<String>, identifier: String) {
        self.title = title; _text = text; self.identifier = identifier
    }
    var body: some View {
        Section(title) {
            TextEditor(text: $text).frame(minHeight: 72)
                .accessibilityLabel(title).accessibilityIdentifier("Experiments.\(identifier)")
        }
    }
}

private struct ExperimentPriorityPicker: View {
    @Binding var priority: ExperimentPriority
    var body: some View {
        Picker("優先度", selection: $priority) {
            ForEach(ExperimentPriority.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }
}

private struct ExperimentStatusPicker: View {
    @Binding var status: ExperimentStatus
    let choices: [ExperimentStatus]
    var body: some View {
        Picker("ステータス", selection: $status) {
            ForEach(choices, id: \.self) { Text($0.title).tag($0) }
        }
    }
}
