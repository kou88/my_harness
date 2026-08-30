import SwiftUI

struct AIConversationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let id: String
    @Bindable var state: AIChatState
    @State private var showSettings = false
    @State private var showDelete = false
    @State private var showRename = false
    @State private var title = ""
    @State private var following = true

    var body: some View {
        VStack(spacing: 0) {
            AIModelMenu(state: state, showSettings: $showSettings).padding(.horizontal, 16).padding(.vertical, 8)
            if let detail = state.detail, detail.id == id {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            ForEach(detail.runs) { run in AIRunView(run: run, state: state).id(run.id) }
                            Color.clear.frame(height: 1).id("bottom")
                                .onAppear { following = true }.onDisappear { following = false }
                        }.padding(16)
                    }
                    .onChange(of: detail.runs.last?.lastSeq) { _, _ in
                        if following { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: detail.runs.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .overlay(alignment: .bottomTrailing) {
                        if !following {
                            Button { proxy.scrollTo("bottom", anchor: .bottom); following = true } label: { Image(systemName: "arrow.down").padding(12).background(.regularMaterial, in: Circle()) }
                                .padding().accessibilityLabel("最新のメッセージへ")
                        }
                    }
                }
            } else if state.isLoading { ProgressView("読み込み中").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ContentUnavailableView("会話を読み込めません", systemImage: "bubble.left", description: Text(state.errorMessage)) }
            if !state.connectionMessage.isEmpty { Text(state.connectionMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
            if !state.errorMessage.isEmpty { Text(state.errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal).textSelection(.enabled) }
        }
        .safeAreaInset(edge: .bottom) {
            AIComposer(state: state, conversationId: id) { _ in }.padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle(state.detail?.id == id ? state.detail!.title : "AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("名前を変更", systemImage: "pencil") { title = state.detail?.title ?? ""; showRename = true }
                    Button("会話を削除", systemImage: "trash", role: .destructive) { showDelete = true }.disabled(state.activeRun != nil)
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task(id: id) { await state.openConversation(id: id) }
        .onDisappear { state.closeConversation() }
        .sheet(isPresented: $showSettings) {
            if let model = state.selectedModel, let settings = state.settings { AISettingsView(model: model, draft: settings) { state.saveSettings($0) } }
        }
        .alert("会話を削除しますか？", isPresented: $showDelete) {
            Button("削除", role: .destructive) { Task { if await state.delete(id) { dismiss() } } }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("MyHarnessの会話履歴と実行イベントを削除します。Hermesのmemoryと作成したファイルは残ります。") }
        .alert("会話の名前", isPresented: $showRename) {
            TextField("名前", text: $title)
            Button("保存") { Task { await state.rename(title) } }
            Button("キャンセル", role: .cancel) {}
        }
    }
}

private struct AIRunView: View {
    let run: AIRun
    @Bindable var state: AIChatState
    @State private var expanded = false
    private var trace: AITrace { state.trace(run.id) }
    private var status: String {
        if run.cancelRequested && run.isActive { return "停止を要求中" }
        if !trace.status.isEmpty && run.isActive { return trace.status }
        if run.status == "queued" { return "実行待ち" }
        if run.status == "running" {
            if trace.tools.contains(where: { !$0.completed }) { return "ツール実行中" }
            if run.outputText.isEmpty && !trace.reasoning.isEmpty { return "思考中" }
            return run.outputText.isEmpty ? "初期化中" : "回答中"
        }
        return run.status == "failed" ? "実行失敗" : run.status == "cancelled" ? "停止済み" : "完了"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 28)
                Text(run.inputText).textSelection(.enabled).padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 7) {
                if run.isActive { ProgressView().controlSize(.small) }
                Text(status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("AI.runStatus")
                Spacer()
                Text(run.model).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if !trace.reasoning.isEmpty {
                        DisclosureGroup("思考") {
                            Text(trace.reasoning).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(trace.tools) { tool in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("入力").font(.caption.bold())
                                AICodeBlock(text: tool.displayArguments)
                                if tool.completed {
                                    Text("結果").font(.caption.bold())
                                    AICodeBlock(text: tool.displayOutput)
                                }
                            }.padding(.top, 6)
                        } label: {
                            Label(tool.name == "execute_code" ? "コード実行" : tool.name, systemImage: tool.name == "execute_code" ? "terminal" : "wrench.and.screwdriver")
                                .font(.subheadline)
                        }
                    }
                    if let usage = trace.events.last(where: { $0.type == "usage" })?.data["usage"] {
                        DisclosureGroup("使用トークン") { AICodeBlock(text: usage.formatted) }
                    }
                    if trace.events.isEmpty { ProgressView("実行履歴を読み込み中") }
                }.padding(.vertical, 8)
            } label: {
                Text("実行詳細" + (trace.tools.isEmpty ? "" : " · ツール \(trace.tools.count)件")).font(.subheadline)
            }
            .onChange(of: expanded) { _, value in if value { Task { await state.loadTrace(run.id) } } }
            if !run.outputText.isEmpty {
                ProductOpsMarkdownView(markdown: run.outputText)
                Button { UIPasteboard.general.string = run.outputText } label: { Image(systemName: "doc.on.doc").font(.caption) }
                    .foregroundStyle(.secondary).accessibilityLabel("回答をコピー")
            }
            if !run.error.isEmpty { Text(run.error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AICodeBlock: View {
    let text: String
    var body: some View {
        ScrollView(.horizontal) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(10)
        }.background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
