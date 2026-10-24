import SwiftUI

private struct ExperimentBadge: View {
    let status: ExperimentStatus
    private var color: Color {
        switch status {
        case .supported, .completed: .green
        case .refuted, .canceled: .red
        case .paused, .inconclusive: .orange
        case .testing, .active, .inProgress: .blue
        case .unverified, .pending, .closed: .secondary
        }
    }
    var body: some View {
        Text(status.title).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct ThemeListView: View {
    @Bindable var state: ExperimentState
    @State private var editor: ThemeCreatePresentation?
    @State private var createdTheme: ExperimentTheme?
    @State private var themeToOpen: ExperimentTheme?
    @State private var creationError = ""

    var body: some View {
        List {
            if !state.isSignedIn {
                Button("ログイン") { Task { await state.signIn() } }
            } else {
                ForEach(state.themes) { theme in
                    NavigationLink {
                        ThemeDetailView(state: state, id: theme.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(theme.title).font(.headline)
                                Spacer(minLength: 8)
                                ExperimentBadge(status: theme.status)
                            }
                            HStack(spacing: 12) {
                                Text("仮説 \(theme.hypothesisCount)")
                                Text("検証中 \(theme.testingHypothesisCount)")
                                Text("TODO \(theme.openTaskCount)")
                                Spacer(minLength: 0)
                                Text(theme.lastActivityAt, format: .dateTime.month().day())
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                }
                if state.hasMore { Button("さらに読み込む") { Task { await state.loadMore() } } }
            }
            switch state.phase {
            case .idle: EmptyView()
            case .loading: ProgressView().frame(maxWidth: .infinity)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Text(message).foregroundStyle(.red)
                    Button("再読み込み") { Task { await state.refresh() } }
                }
            case .loaded:
                if state.themes.isEmpty {
                    ContentUnavailableView("テーマはありません", systemImage: "flask")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("テーマ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    do { editor = ThemeCreatePresentation(id: UUID(), session: try state.sessionStamp()) }
                    catch { creationError = error.localizedDescription }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("テーマを追加")
                .accessibilityIdentifier("Experiments.theme.add")
                .disabled(!state.isSignedIn)
            }
        }
        .sheet(item: $editor, onDismiss: {
            themeToOpen = createdTheme
            createdTheme = nil
        }) { presentation in
            NavigationStack {
                ExperimentThemeCreateView(state: state, presentation: presentation) { createdTheme = $0 }
            }
        }
        .navigationDestination(item: $themeToOpen) { theme in
            ThemeDetailView(state: state, id: theme.id)
        }
        .alert("追加できません", isPresented: Binding(get: { !creationError.isEmpty }, set: { if !$0 { creationError = "" } })) {
            Button("閉じる", role: .cancel) { }
        } message: { Text(creationError) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cognitoDidSignOut"))) { _ in
            editor = nil; createdTheme = nil; themeToOpen = nil
        }
        .task { if state.isSignedIn { await state.refresh() } }
        .refreshable { await state.refresh() }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 9 * 3600)!)
        .accessibilityIdentifier("Experiments.list")
    }
}

private struct ThemeCreatePresentation: Identifiable {
    let id: UUID
    let session: String
}

enum ExperimentCreationPhase<Request> {
    case editing, saving, rejected(String), uncertain(Request, String), saved
    var isSaving: Bool { if case .saving = self { true } else { false } }
    var inputsLocked: Bool {
        switch self { case .saving, .uncertain, .saved: true; case .editing, .rejected: false }
    }
    var message: String {
        switch self { case .rejected(let message), .uncertain(_, let message): message; default: "" }
    }
    var buttonTitle: String {
        switch self { case .saving: "追加中"; case .uncertain: "再試行"; default: "追加" }
    }
}

private struct ExperimentThemeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let state: ExperimentState
    let presentation: ThemeCreatePresentation
    let onCreated: (ExperimentTheme) -> Void
    @State private var draft = ExperimentThemeDraft.empty
    @State private var phase: ExperimentCreationPhase<ExperimentThemeCreateRequest> = .editing
    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            if !phase.message.isEmpty { Text(phase.message).foregroundStyle(.red) }
            else if !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !draft.validationMessage.isEmpty {
                Text(draft.validationMessage).foregroundStyle(.red)
            }
            Group {
                Section {
                    TextField("テーマ名", text: $draft.title, axis: .vertical)
                        .lineLimit(1...3).focused($titleFocused)
                        .accessibilityIdentifier("Experiments.theme.title")
                    Picker("ステータス", selection: $draft.status) {
                        ForEach([ExperimentStatus.active, .paused, .closed], id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }
                Section("概要・目的") { TextEditor(text: $draft.description).frame(minHeight: 80).accessibilityLabel("概要・目的") }
                Section("対象市場・対象者") { TextEditor(text: $draft.audience).frame(minHeight: 60).accessibilityLabel("対象市場・対象者") }
                Section("制約・前提条件") { TextEditor(text: $draft.constraints).frame(minHeight: 60).accessibilityLabel("制約・前提条件") }
            }.disabled(phase.inputsLocked)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("テーマを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }.disabled(phase.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(phase.buttonTitle) { Task { await save() } }
                    .disabled(phase.isSaving || draft.validationMessage != "" || isSaved)
                    .accessibilityIdentifier("Experiments.theme.save")
            }
        }
        .interactiveDismissDisabled(phase.isSaving)
        .task { titleFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cognitoDidSignOut"))) { _ in dismiss() }
    }

    private var isSaved: Bool { if case .saved = phase { true } else { false } }

    private func save() async {
        guard !phase.isSaving, !isSaved else { return }
        let request: ExperimentThemeCreateRequest
        do {
            if case .uncertain(let pending, _) = phase { request = pending }
            else { request = try ExperimentThemeCreateRequest(operationID: presentation.id, draft: draft) }
        } catch { phase = .rejected(error.localizedDescription); return }
        phase = .saving
        do {
            let theme = try await state.createTheme(request, session: presentation.session)
            phase = .saved
            onCreated(theme)
            dismiss()
        } catch let error as ActionInboxAPIClient.ClientError {
            if case .requestFailed(let status, _) = error, [400, 401, 403, 404, 422].contains(status) {
                phase = .rejected(error.localizedDescription)
            } else { phase = .uncertain(request, error.localizedDescription) }
        } catch { phase = .uncertain(request, error.localizedDescription) }
    }
}

private enum ExperimentRemotePhase<Value> {
    case idle, loading, loaded(Value), failed(String)
}

private struct ExperimentRemoteView<Value, Content: View>: View {
    let state: ExperimentState
    let load: (ExperimentAPIClient) async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @State private var phase: ExperimentRemotePhase<Value> = .idle
    @State private var requestID = UUID()

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading: ProgressView()
            case .loaded(let value): content(value)
            case .failed(let message):
                ContentUnavailableView {
                    Label("読み込めません", systemImage: "exclamationmark.circle")
                } description: { Text(message) } actions: { Button("再読み込み") { Task { await refresh() } } }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cognitoDidSignOut"))) { _ in
            requestID = UUID(); phase = .failed("ログインしてください")
        }
    }
    private func refresh() async {
        let request = UUID(); requestID = request; phase = .loading
        do {
            let api = try state.client(); let stamp = try state.sessionStamp()
            let value = try await load(api)
            guard state.isCurrent(stamp), requestID == request else { return }
            phase = .loaded(value)
        } catch is CancellationError { }
        catch { if requestID == request { phase = .failed(error.localizedDescription) } }
    }
}

private struct ExperimentTextSection: View {
    let title: String
    let text: String
    var body: some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section(title) { ProductOpsMarkdownView(markdown: text) }
        }
    }
}

private enum ThemeSection: String, CaseIterable, Identifiable {
    case hypotheses, tasks, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hypotheses: "仮説"
        case .tasks: "検証TODO"
        case .notes: "結果ノート"
        }
    }
}

struct ThemeDetailView: View {
    let state: ExperimentState
    let id: String
    @State private var section: ThemeSection = .hypotheses
    @State private var editor: ExperimentItemCreatePresentation?
    @State private var creationError = ""
    @State private var didCreate = false
    @State private var refreshID = UUID()

    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.get("themes/\(id)/tree", query: [], as: ExperimentTree.self) }) { tree in
            List {
                switch section {
                case .hypotheses:
                    if tree.visibleHypotheses.isEmpty {
                        ContentUnavailableView("仮説はありません", systemImage: "lightbulb")
                    }
                    ForEach(tree.visibleHypotheses) { hypothesis in
                        hypothesisLink(hypothesis, tree: tree)
                    }
                case .tasks:
                    if tree.visibleTasks.isEmpty {
                        ContentUnavailableView("検証TODOはありません", systemImage: "checklist")
                    }
                    ForEach(tree.visibleHypotheses.filter { !tree.tasks(for: $0).isEmpty }) { hypothesis in
                        Section(hypothesis.statement) {
                            ForEach(tree.tasks(for: hypothesis)) { task in
                                NavigationLink {
                                    VerificationTaskDetailView(state: state, id: task.id)
                                } label: { ExperimentTaskRow(task: task) }
                            }
                        }
                    }
                case .notes:
                    if tree.visibleNotes.isEmpty {
                        ContentUnavailableView("結果ノートはありません", systemImage: "note.text")
                    }
                    ForEach(tree.visibleTasks.filter { !tree.notes(for: $0).isEmpty }) { task in
                        Section(task.title) {
                            ForEach(tree.notes(for: task)) { note in
                                NavigationLink {
                                    ResultNoteDetailView(state: state, id: note.id)
                                } label: { ExperimentNoteRow(note: note) }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .id(section)
            .safeAreaInset(edge: .top) {
                Picker("テーマ内の表示", selection: $section) {
                    ForEach(ThemeSection.allCases) { section in Text(section.title).tag(section) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier("Experiments.theme.tabs")
            }
            .navigationTitle(tree.theme.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExperimentThemeInfoView(theme: tree.theme)
                    } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("テーマの詳細")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        do {
                            editor = ExperimentItemCreatePresentation(id: UUID(), session: try state.sessionStamp(), kind: section.creationKind, tree: tree, assigneeID: try state.currentAssigneeID())
                        } catch { creationError = error.localizedDescription }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("\(section.title)を追加")
                    .accessibilityIdentifier("Experiments.\(section.creationKind.rawValue).add")
                }
            }
        }
        .id(refreshID)
        .sheet(item: $editor, onDismiss: {
            if didCreate {
                refreshID = UUID(); didCreate = false
                Task { await state.refresh() }
            }
        }) { presentation in
            NavigationStack {
                ExperimentItemCreateView(state: state, presentation: presentation) { didCreate = true }
            }
        }
        .alert("追加できません", isPresented: Binding(get: { !creationError.isEmpty }, set: { if !$0 { creationError = "" } })) {
            Button("閉じる", role: .cancel) { }
        } message: { Text(creationError) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cognitoDidSignOut"))) { _ in editor = nil }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("Experiments.theme")
    }
    private func hypothesisLink(_ hypothesis: ExperimentHypothesis, tree: ExperimentTree) -> some View {
        NavigationLink {
            HypothesisDetailView(state: state, themeID: id, id: hypothesis.id)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(hypothesis.statement)
                HStack {
                    let tasks = tree.tasks(for: hypothesis)
                    let completed = tasks.filter { $0.status == .completed }.count
                    Label("\(completed)/\(tasks.count)", systemImage: "checklist")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("TODO \(completed) / \(tasks.count) 完了")
                    Spacer()
                    ExperimentBadge(status: hypothesis.status)
                }
            }.padding(.vertical, 3)
        }
    }
}

private extension ThemeSection {
    var creationKind: ExperimentItemKind {
        switch self { case .hypotheses: .hypothesis; case .tasks: .task; case .notes: .note }
    }
}

private struct ExperimentThemeInfoView: View {
    let theme: ExperimentTheme
    var body: some View {
        List {
            Section {
                ExperimentBadge(status: theme.status)
                if !theme.description.isEmpty { ProductOpsMarkdownView(markdown: theme.description) }
            }
            ExperimentTextSection(title: "対象", text: theme.audience)
            ExperimentTextSection(title: "前提・制約", text: theme.constraints)
        }
        .listStyle(.plain)
        .navigationTitle("テーマの詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HypothesisDetailView: View {
    let state: ExperimentState
    let themeID: String
    let id: String
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.get("themes/\(themeID)/tree", query: [], as: ExperimentTree.self) }) { tree in
            if let hypothesis = tree.hypotheses.first(where: { $0.id == id }) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(hypothesis.statement).font(.title3.weight(.semibold))
                            ExperimentBadge(status: hypothesis.status)
                        }.padding(.vertical, 4)
                    }
                    ExperimentTextSection(title: "背景", text: hypothesis.background)
                    ExperimentTextSection(title: "確認すること", text: hypothesis.question)
                    ExperimentTextSection(title: "成功基準", text: hypothesis.successCriteria)
                    ExperimentTextSection(title: "反証基準", text: hypothesis.falsificationCriteria)
                    Section("TODO") {
                        ForEach(tree.tasks(for: hypothesis)) { task in
                            DisclosureGroup {
                                NavigationLink("検証内容") { VerificationTaskDetailView(state: state, id: task.id) }
                                ForEach(tree.notes(for: task)) { note in
                                    NavigationLink { ResultNoteDetailView(state: state, id: note.id) } label: { ExperimentNoteRow(note: note) }
                                }
                            } label: { ExperimentTaskRow(task: task) }
                        }
                    }
                    Section("判定") {
                        ForEach(tree.judgments.filter { $0.hypothesisId == id }) { judgment in
                            NavigationLink {
                                ExperimentJudgmentView(state: state, hypothesisID: id, judgmentID: judgment.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { ExperimentBadge(status: judgment.decision); Spacer(); Text(judgment.createdAt, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary) }
                                    Text(judgment.reason).lineLimit(3)
                                    if judgment.hypothesisRevisionId != hypothesis.definitionRevisionId { Text("旧基準").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }.listStyle(.plain)
            } else { ContentUnavailableView("仮説が見つかりません", systemImage: "questionmark") }
        }.navigationTitle("仮説").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExperimentTaskRow: View {
    let task: ExperimentTask
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
            HStack {
                ExperimentBadge(status: task.status)
                if let due = task.dueAt { Spacer(); Text(due, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(task.isFinished || due >= Date() ? Color.secondary : Color.red) }
            }
        }.padding(.vertical, 3)
    }
}

private struct ExperimentNoteRow: View {
    let note: ExperimentNote
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(note.title)
            Spacer(minLength: 8)
            Text(note.observedAt, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}

private struct ExperimentTaskDetail {
    let task: ExperimentTask
    let tree: ExperimentTree
}

struct VerificationTaskDetailView: View {
    let state: ExperimentState
    let id: String
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in
            let task = try await api.get("tasks/\(id)", query: [], as: ExperimentTask.self)
            let hypothesis = try await api.get("hypotheses/\(task.hypothesisId)", query: [], as: ExperimentHypothesis.self)
            let tree = try await api.get("themes/\(hypothesis.themeId)/tree", query: [], as: ExperimentTree.self)
            guard let current = tree.tasks.first(where: { $0.id == id }) else { throw ActionInboxAPIClient.ClientError.invalidResponse }
            return ExperimentTaskDetail(task: current, tree: tree)
        }) { detail in
            List {
                Section {
                    Text(detail.task.title).font(.title3.weight(.semibold))
                    HStack { ExperimentBadge(status: detail.task.status); Spacer(); if let due = detail.task.dueAt { Text(due, format: .dateTime.year().month().day().hour().minute()).font(.caption) } }
                }
                ExperimentTextSection(title: "実施内容", text: detail.task.method)
                ExperimentTextSection(title: "成果物・測定項目", text: detail.task.expectedOutcome)
                ExperimentTextSection(title: "実施結果", text: detail.task.completionReason)
                Section {
                    NavigationLink("検証時の仮説") { ExperimentHypothesisRevisionView(state: state, revisionID: detail.task.hypothesisRevisionId) }
                }
                Section("結果") {
                    ForEach(detail.tree.notes(for: detail.task)) { note in
                        NavigationLink { ResultNoteDetailView(state: state, id: note.id) } label: { ExperimentNoteRow(note: note) }
                    }
                }
            }.listStyle(.plain)
        }.navigationTitle("TODO").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExperimentHypothesisRevisionView: View {
    let state: ExperimentState
    let revisionID: String
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.get("revisions/\(revisionID)", query: [], as: ExperimentRevision<ExperimentHypothesis>.self) }) { revision in
            List {
                Section { Text(revision.snapshot.statement).font(.headline) }
                ExperimentTextSection(title: "確認すること", text: revision.snapshot.question)
                ExperimentTextSection(title: "成功基準", text: revision.snapshot.successCriteria)
                ExperimentTextSection(title: "反証基準", text: revision.snapshot.falsificationCriteria)
            }
        }.navigationTitle("検証時の仮説").navigationBarTitleDisplayMode(.inline)
    }
}

struct ResultNoteDetailView: View {
    let state: ExperimentState
    let id: String
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.get("notes/\(id)", query: [], as: ExperimentNote.self) }) { note in
            List {
                ExperimentNoteContent(note: note)
                Section {
                    NavigationLink("履歴（\(note.version)）") { ExperimentNoteHistoryView(state: state, id: id) }
                }
            }.listStyle(.plain)
        }.navigationTitle("結果").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExperimentNoteContent: View {
    let note: ExperimentNote
    var body: some View {
        Section {
            Text(note.title).font(.title3.weight(.semibold))
            Text(note.observedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
        }
        ExperimentTextSection(title: "観測した事実", text: note.facts)
        ExperimentTextSection(title: "解釈・考察", text: note.interpretation)
        if !note.sources.isEmpty {
            Section("参照元") { ForEach(Array(note.sources.enumerated()), id: \.offset) { _, source in Link(source.label, destination: source.url) } }
        }
        ExperimentTextSection(title: "判明したこと", text: note.findings)
        ExperimentTextSection(title: "未解決", text: note.unresolved)
        ExperimentTextSection(title: "次の検証", text: note.nextCandidates)
    }
}

private struct ExperimentNoteHistoryView: View {
    let state: ExperimentState
    let id: String
    @State private var offset = 0
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.page("notes/\(id)/history", offset: offset, query: [], as: ExperimentRevision<ExperimentNote>.self) }) { page in
            List {
                ForEach(page.items) { revision in
                    NavigationLink {
                        List {
                            ExperimentNoteContent(note: revision.snapshot)
                            ExperimentTextSection(title: "変更理由", text: revision.reason)
                        }.navigationTitle("v\(revision.version)")
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("v\(revision.version)"); Spacer(); Text(revision.createdAt, format: .dateTime.year().month().day()).foregroundStyle(.secondary) }
                            Text(revision.reason)
                        }
                    }
                }
                if page.hasMore { Button("次の50件") { offset += page.limit } }
                if offset > 0 { Button("前の50件") { offset = max(0, offset - page.limit) } }
            }
        }.id(offset).navigationTitle("履歴").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExperimentJudgmentView: View {
    let state: ExperimentState
    let hypothesisID: String
    let judgmentID: String
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.get("hypotheses/\(hypothesisID)/judgments", query: [], as: [ExperimentJudgmentDetail].self) }) { judgments in
            if let judgment = judgments.first(where: { $0.id == judgmentID }) {
                List {
                    Section { ExperimentBadge(status: judgment.decision); ProductOpsMarkdownView(markdown: judgment.reason) }
                    Section {
                        NavigationLink("判定時の仮説") { ExperimentHypothesisRevisionView(state: state, revisionID: judgment.hypothesisRevisionId) }
                    }
                    Section("根拠") {
                        ForEach(Array(judgment.evidenceRevisionIds.enumerated()), id: \.element) { index, revisionID in
                            NavigationLink("結果 \(index + 1)") {
                                ExperimentRemoteView(state: state, load: { api in try await api.get("revisions/\(revisionID)", query: [], as: ExperimentRevision<ExperimentNote>.self) }) { revision in List { ExperimentNoteContent(note: revision.snapshot) } }
                                    .navigationTitle("判定時の結果").navigationBarTitleDisplayMode(.inline)
                            }
                        }
                    }
                }
            } else { ContentUnavailableView("判定が見つかりません", systemImage: "questionmark") }
        }.navigationTitle("判定").navigationBarTitleDisplayMode(.inline)
    }
}
