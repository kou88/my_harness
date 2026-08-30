import SwiftUI

struct AIHarnessSetup: View {
    @Bindable var state: AIChatState
    @State private var showRepositories = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(AIHarness.allCases) { harness in
                    Button { state.chooseHarness(harness) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(harness.name, systemImage: harness.symbol).font(.system(size: 14, weight: .medium))
                            Text(harness == .hermes ? "チャット・調査" : "repoの実装・PR")
                                .font(.system(size: 12)).foregroundStyle(AIChatStyle.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(state.harness == harness ? AIChatStyle.bubble : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.harness == harness ? AIChatStyle.focusedBorder : AIChatStyle.border))
                    }.buttonStyle(AIChatRowButtonStyle()).accessibilityIdentifier("AI.harness." + harness.rawValue)
                        .accessibilityAddTraits(state.harness == harness ? .isSelected : [])
                }
            }.disabled(state.isSending || state.hasPendingSubmission)
            if state.harness == .opencode {
                Button { showRepositories = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 3) {
                            if case .selected(let repo, let branch) = state.repositorySelection {
                                Text(repo.repository).lineLimit(1).truncationMode(.middle)
                                Text(branch).font(.caption).foregroundStyle(AIChatStyle.muted)
                            } else { Text("repoと開始ブランチを選択") }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.system(size: 14)).padding(.horizontal, 12).frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(AIChatRowButtonStyle()).accessibilityIdentifier("AI.repository")
                    .disabled(state.isSending || state.hasPendingSubmission)
                Text("会話専用のブランチで作業します。共有モードの実行枠はHermesと共通です。")
                    .font(.caption).foregroundStyle(AIChatStyle.muted).padding(.horizontal, 4)
            }
        }.sheet(isPresented: $showRepositories) { AIRepositoryPicker(state: state) }
    }
}

private struct AIRepositoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: AIChatState
    @State private var query = ""
    private var repositories: [AIRepository] {
        state.repositories.filter { query.isEmpty || $0.repository.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if repositories.isEmpty {
                    Text(state.repositories.isEmpty ? "利用可能なrepoがありません。GitHub Appの権限と実行PCの接続を確認してください。" : "該当するrepoがありません")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(repositories) { repo in
                    Section {
                        ForEach(repo.branches, id: \.self) { branch in
                            Button {
                                state.chooseRepository(repo, branch: branch); dismiss()
                            } label: {
                                HStack {
                                    Text(branch)
                                    Spacer()
                                    if case .selected(let selected, let current) = state.repositorySelection, selected.id == repo.id, current == branch { Image(systemName: "checkmark") }
                                }.frame(minHeight: 32).contentShape(Rectangle())
                            }.disabled(!repo.online || (state.sharedMode && state.selectedModel?.hostId != repo.hostId))
                        }
                    } header: { Text(repo.repository) } footer: { Text(repo.online ? repo.hostName : "オフライン") }
                }
            }.searchable(text: $query, prompt: "repoを検索")
                .navigationTitle("作業するrepo").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
                .refreshable { await state.loadList() }
        }
    }
}

struct AICodingResult: View {
    let trace: AITrace
    let runID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let diff = trace.events.last(where: { $0.type == "work.diff" }), case .array(let files) = diff.data["files"], !files.isEmpty {
                AITraceDisclosure(title: "変更ファイル · \(files.count)件", icon: "doc.text", completed: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(files.enumerated()), id: \.offset) { item in
                            if case .string(let path) = item.element { Text(path).font(.caption.monospaced()).textSelection(.enabled) }
                        }
                        AIChatCodeBlock(title: "差分", text: diff.text("patch"), copyID: runID + ".diff")
                        if diff.data["truncated"] == .bool(true) { Text("差分は表示上限までです。全体は作業repoまたはPRで確認できます。").font(.caption).foregroundStyle(AIChatStyle.muted) }
                    }
                }
            }
            if let pr = trace.events.last(where: { $0.type == "work.pr" }), let url = URL(string: pr.text("url")), url.scheme == "https", url.host == "github.com" {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "arrow.triangle.pull")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("GitHubでPRを開く").font(.system(size: 14, weight: .medium))
                            Text(pr.text("branch")).font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }.padding(12).background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(AIChatRowButtonStyle()).accessibilityIdentifier("AI.pullRequest")
                if case .array(let checks) = pr.data["checks"] {
                    if checks.isEmpty { Text("CIの結果はGitHubで確認できます。").font(.caption).foregroundStyle(AIChatStyle.muted) }
                    ForEach(Array(checks.enumerated()), id: \.offset) { item in
                        if case .object(let check) = item.element, case .string(let name) = check["name"], case .string(let status) = check["conclusion"] {
                            Text("\(name) · \(status)").font(.caption).foregroundStyle(AIChatStyle.muted)
                        }
                    }
                }
            }
        }
    }
}

struct AIAgentRequestView: View {
    let request: AIRequest
    @Bindable var state: AIChatState
    @State private var answers: [Int: Set<String>] = [:]
    @State private var freeText: [Int: String] = [:]

    private var questions: [[String: AIJSON]] {
        guard case .array(let values) = request.payload["questions"] else { return [] }
        return values.compactMap { if case .object(let object) = $0 { return object }; return nil }
    }
    private func text(_ object: [String: AIJSON], _ key: String) -> String {
        if case .string(let value) = object[key] { return value }; return ""
    }
    private var responses: [[String]] {
        questions.indices.map { index in
            let input = (freeText[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Array(answers[index] ?? []).sorted() + (input.isEmpty ? [] : [input])
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(request.kind == "permission" ? "実行の確認" : "OpenCodeからの質問", systemImage: "hand.raised")
                .font(.system(size: 14, weight: .semibold))
            if request.kind == "permission" {
                Text(text(request.payload, "permission")).font(.caption).foregroundStyle(AIChatStyle.muted)
                if case .array(let patterns) = request.payload["patterns"] {
                    ForEach(Array(patterns.enumerated()), id: \.offset) { item in
                        if case .string(let value) = item.element { AISelectableText(text: value, kind: .code) }
                    }
                }
                HStack(spacing: 12) {
                    Button("許可しない") { Task { await state.answer(request, reply: .permission(allow: false)) } }
                    Spacer()
                    Button("今回だけ許可") { Task { await state.answer(request, reply: .permission(allow: true)) } }
                }.buttonStyle(.bordered)
            } else {
                ForEach(Array(questions.enumerated()), id: \.offset) { item in
                    let index = item.offset
                    let question = item.element
                    Text(text(question, "question")).font(.callout).textSelection(.enabled)
                    if case .array(let options) = question["options"] {
                        ForEach(Array(options.enumerated()), id: \.offset) { option in
                            if case .object(let values) = option.element {
                                let label = text(values, "label")
                                Button {
                                    var selection = answers[index] ?? []
                                    if selection.contains(label) { selection.remove(label) }
                                    else if question["multiple"] == .bool(true) { selection.insert(label) }
                                    else { selection = [label]; freeText[index] = "" }
                                    answers[index] = selection
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: answers[index]?.contains(label) == true ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(label)
                                            Text(text(values, "description")).font(.caption).foregroundStyle(AIChatStyle.muted)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
                                }.buttonStyle(AIChatRowButtonStyle())
                            }
                        }
                    }
                    if question["custom"] != .bool(false) {
                        TextField("回答を入力", text: Binding(get: { freeText[index] ?? "" }, set: { value in
                            freeText[index] = value
                            if question["multiple"] != .bool(true) { answers[index] = [] }
                        }), axis: .vertical).textFieldStyle(.roundedBorder)
                    }
                }
                HStack {
                    Button("回答を中止") { Task { await state.answer(request, reply: .question(answers: [], rejected: true)) } }
                    Spacer()
                    Button("回答する") { Task { await state.answer(request, reply: .question(answers: responses, rejected: false)) } }
                        .disabled(questions.isEmpty || responses.contains(where: \.isEmpty))
                }.buttonStyle(.bordered)
            }
        }.font(.system(size: 14)).padding(14).background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 12))
            .disabled(state.replying.contains(request.id) || request.status != "pending")
            .overlay(alignment: .bottom) {
                if request.status == "answered" { Text("回答をPCへ送信中").font(.caption).padding(6).background(AIChatStyle.surface) }
            }
    }
}
