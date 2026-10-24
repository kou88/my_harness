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

    var body: some View {
        List {
            if !state.isSignedIn {
                Button("ログイン") { Task { await state.signIn() } }
            } else {
                Picker("表示", selection: $state.focus) {
                    ForEach(ExperimentFocus.allCases) { focus in Text(focus.title).tag(focus) }
                }.pickerStyle(.menu).labelsHidden()
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
                ForEach(state.tasks) { task in
                    NavigationLink {
                        VerificationTaskDetailView(state: state, id: task.id)
                    } label: { ExperimentTaskRow(task: task) }
                }
                ForEach(state.notes) { note in
                    NavigationLink { ResultNoteDetailView(state: state, id: note.id) } label: { ExperimentNoteRow(note: note) }
                }
                ForEach(state.hypotheses) { hypothesis in
                    NavigationLink {
                        HypothesisDetailView(state: state, themeID: hypothesis.themeId, id: hypothesis.id)
                    } label: {
                        HStack { Text(hypothesis.statement); Spacer(); ExperimentBadge(status: hypothesis.status) }
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
                if state.themes.isEmpty && state.tasks.isEmpty && state.notes.isEmpty && state.hypotheses.isEmpty {
                    ContentUnavailableView(state.focus == .themes ? "テーマはありません" : "該当する項目はありません", systemImage: "flask")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("テーマ")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: state.focus) { if state.isSignedIn { await state.refresh() } }
        .refreshable { await state.refresh() }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 9 * 3600)!)
        .accessibilityIdentifier("Experiments.list")
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

struct ThemeDetailView: View {
    let state: ExperimentState
    let id: String
    var body: some View {
        ExperimentRemoteView(state: state, load: { api in try await api.get("themes/\(id)/tree", query: [], as: ExperimentTree.self) }) { tree in
            List {
                Section {
                    HStack { Text(tree.theme.title).font(.title3.weight(.semibold)); Spacer(); ExperimentBadge(status: tree.theme.status) }
                    if !tree.theme.description.isEmpty { ProductOpsMarkdownView(markdown: tree.theme.description) }
                }
                ExperimentTextSection(title: "対象", text: tree.theme.audience)
                ExperimentTextSection(title: "前提・制約", text: tree.theme.constraints)
                Section("仮説") {
                    ForEach(tree.hypotheses.filter { $0.archivedAt == nil }) { hypothesis in
                        NavigationLink {
                            HypothesisDetailView(state: state, themeID: id, id: hypothesis.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(hypothesis.statement)
                                HStack {
                                    let tasks = tree.tasks(for: hypothesis)
                                    Label("\(tasks.filter { $0.status == .completed }.count)/\(tasks.count)", systemImage: "checklist")
                                        .font(.caption).foregroundStyle(.secondary).accessibilityLabel("TODO \(tasks.filter { $0.status == .completed }.count) / \(tasks.count) 完了")
                                    Spacer(); ExperimentBadge(status: hypothesis.status)
                                }
                            }.padding(.vertical, 3)
                        }
                    }
                }
                Section("最近の結果") {
                    ForEach(recentNotes(tree)) { note in
                        NavigationLink { ResultNoteDetailView(state: state, id: note.id) } label: { ExperimentNoteRow(note: note) }
                    }
                }
            }.listStyle(.plain)
        }
        .navigationTitle("テーマ").navigationBarTitleDisplayMode(.inline)
    }
    private func recentNotes(_ tree: ExperimentTree) -> [ExperimentNote] {
        let hypotheses = Set(tree.hypotheses.filter { $0.archivedAt == nil }.map(\.id))
        let tasks = Set(tree.tasks.filter { $0.archivedAt == nil && hypotheses.contains($0.hypothesisId) }.map(\.id))
        return Array(tree.notes.filter { $0.archivedAt == nil && tasks.contains($0.taskId) }.sorted { $0.createdAt > $1.createdAt }.prefix(5))
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
