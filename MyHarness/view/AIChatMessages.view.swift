import SwiftUI

struct AIMessageList: View {
    let detail: AIConversationDetail
    @Bindable var state: AIChatState
    @State private var following = true
    @State private var userScrolling = false
    @State private var distanceFromBottom: CGFloat = 0

    var body: some View {
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView {
                // A run can grow by many screens while streamed text is arriving.
                // Lazy estimates plus scrollTo(onAppear) can restore an offset
                // outside the rendered rows. Measure actual message heights first.
                VStack(alignment: .leading, spacing: 36) {
                    ForEach(detail.runs) { run in AIRunMessage(run: run, state: state).id(run.id) }
                    Color.clear.frame(height: 1).id("bottom")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: AIChatBottomKey.self, value: geometry.frame(in: .named("AI.messageScroll")).maxY)
                        })
                }.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                    .background(GeometryReader { content in
                        Color.clear.preference(key: AIChatContentHeightKey.self, value: content.size.height)
                    })
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .coordinateSpace(name: "AI.messageScroll")
            .onPreferenceChange(AIChatBottomKey.self) { bottom in
                distanceFromBottom = bottom - viewport.size.height
                if userScrolling { following = distanceFromBottom < 90 }
            }
            .simultaneousGesture(DragGesture().onChanged { _ in
                userScrolling = true; following = false
            }.onEnded { _ in
                userScrolling = false; following = distanceFromBottom < 90
            })
            .onPreferenceChange(AIChatContentHeightKey.self) { height in
                // Includes text layout, trace expansion and keyboard/viewport changes.
                // Do not scroll on every SSE event before UIKit has laid out its text.
                if height > 0 && following && !userScrolling { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: detail.runs.count) { _, _ in following = true }
            .overlay(alignment: .bottom) {
                if !following {
                    Button { following = true; proxy.scrollTo("bottom", anchor: .bottom) } label: {
                        Image(systemName: "arrow.down").font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 34).background(AIChatStyle.bubble, in: Circle())
                            .overlay(Circle().stroke(AIChatStyle.border))
                    }.buttonStyle(.plain).padding(.bottom, 6).accessibilityLabel("最新のメッセージへ")
                }
            }
        }
        }
        .accessibilityIdentifier("AI.messages")
    }
}

private struct AIRunMessage: View {
    let run: AIRun
    @Bindable var state: AIChatState
    @State private var showInfo = false
    private var trace: AITrace { state.trace(run.id) }
    private var outputText: String { state.displayedOutput(for: run) }
    private var status: String {
        if run.cancelRequested && run.isActive { return "停止を要求中" }
        if !trace.status.isEmpty && run.isActive { return trace.status }
        if run.status == "queued" { return "待機中（PCで順番に処理します）" }
        if run.status == "running" {
            if trace.tools.contains(where: { !$0.completed }) { return "ツール実行中" }
            if outputText.isEmpty && !trace.reasoning.isEmpty { return "思考中" }
            return outputText.isEmpty ? "初期化中" : "回答中"
        }
        return run.status == "failed" ? "実行失敗" : run.status == "cancelled" ? "停止済み" : "完了"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                HStack {
                    Spacer(minLength: 30)
                    AIChatMessageText(text: run.inputText, kind: .message, copyID: run.id + ".input")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 24))
                }
                Button { UIPasteboard.general.string = run.inputText } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 14))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(AIChatStyle.muted)
                    .accessibilityLabel("送信したメッセージを全文コピー")
                    .accessibilityIdentifier("AI.copyInput.\(run.id)")
            }.padding(.bottom, 12)
            Text(run.model).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                .accessibilityLabel("回答モデル: " + run.model).padding(.bottom, 8)
            if run.isActive || run.status != "completed" {
                HStack(spacing: 7) {
                    if run.isActive { ProgressView().controlSize(.mini).tint(AIChatStyle.muted) }
                    Text(status).font(.system(size: 14)).foregroundStyle(AIChatStyle.muted)
                        .accessibilityIdentifier("AI.runStatus")
                }.padding(.bottom, 10)
            }
            if !trace.reasoning.isEmpty {
                AITraceDisclosure(title: run.isActive && run.outputText.isEmpty ? "思考中" : "思考", icon: "sparkle", completed: !run.isActive) {
                    AIChatMessageText(text: trace.reasoning, kind: .reasoning, copyID: run.id + ".reasoning")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(AIChatStyle.border).frame(width: 2) }
                }.padding(.bottom, 8)
            }
            ForEach(trace.tools) { tool in
                AITraceDisclosure(title: tool.name == "execute_code" ? "コード実行 · execute_code" : tool.name, icon: tool.name == "execute_code" ? "terminal" : "wrench", completed: tool.completed) {
                    VStack(alignment: .leading, spacing: 10) {
                        AIChatCodeBlock(title: tool.name == "execute_code" ? "python" : "入力", text: tool.displayArguments, copyID: run.id + ".tool.\(tool.id).input")
                        if tool.completed { AIChatCodeBlock(title: "結果", text: tool.displayOutput, copyID: run.id + ".tool.\(tool.id).output") }
                    }
                }.padding(.bottom, 8)
            }
            if !outputText.isEmpty {
                AIChatMessageText(text: outputText, kind: .markdown, copyID: run.id + ".output").padding(.top, 2)
                if run.isActive {
                    Capsule().fill(AIChatStyle.muted).frame(width: 3, height: 14).padding(.top, 5)
                        .accessibilityHidden(true)
                }
            }
            AICodingResult(trace: trace, runID: run.id).padding(.top, 8)
            ForEach(state.requestsByRun[run.id] ?? []) { request in
                if run.isActive && ["pending", "answered"].contains(request.status) {
                    AIAgentRequestView(request: request, state: state).padding(.vertical, 10)
                }
            }
            if !run.error.isEmpty { Text(run.error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(.vertical, 8) }
            if !run.isActive {
                HStack(spacing: 0) {
                    Button { UIPasteboard.general.string = run.outputText } label: { Image(systemName: "doc.on.doc").frame(width: 32, height: 36) }
                        .disabled(run.outputText.isEmpty).accessibilityLabel("回答をコピー")
                    Button { showInfo.toggle() } label: { Image(systemName: "info.circle").frame(width: 32, height: 36) }.accessibilityLabel("実行情報")
                }.font(.system(size: 14)).foregroundStyle(AIChatStyle.muted).buttonStyle(.plain).padding(.leading, -7)
            }
            if showInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("推論 \(run.settings.reasoningEffort) · \(run.settings.contextLength / 1024)K · 出力上限 \(run.settings.maxOutputTokens.formatted())")
                    if let usage = trace.events.last(where: { $0.type == "usage" })?.data["usage"] { AIChatCodeBlock(title: "使用トークン", text: usage.formatted, copyID: run.id + ".usage") }
                    ForEach(trace.events.filter { $0.type == "status" && $0.data["done"] == .bool(true) }) { event in
                        Text(event.text("description"))
                    }
                }.font(.caption).foregroundStyle(AIChatStyle.muted).padding(.vertical, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task(id: run.id) { await state.loadTrace(run.id) }
    }
}

struct AITraceDisclosure<Content: View>: View {
    let title: String
    let icon: String
    let completed: Bool
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: completed && icon != "sparkle" ? "checkmark.circle" : icon)
                        .foregroundStyle(completed && icon != "sparkle" ? Color(red: 0.36, green: 0.77, blue: 0.6) : AIChatStyle.muted)
                    Text(title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11))
                }.font(.system(size: 14)).foregroundStyle(AIChatStyle.muted).frame(minHeight: 30)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title + (expanded ? "を閉じる" : "を開く"))
            if expanded { content().padding(.bottom, 8) }
        }
    }
}

private struct AIChatMessageText: View {
    let text: String
    let kind: AISelectableText.Kind
    let copyID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AIMessageContent.parse(text)) { part in
                switch part.kind {
                case .text(let prose):
                    if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        AISelectableText(text: prose.trimmingCharacters(in: .newlines), kind: kind)
                    }
                case .code(let language, let code):
                    if AICodeSyntax.normalizedLanguage(language) == "mermaid" {
                        AIMermaidCodeBlock(text: code, copyID: copyID + ".\(part.id)", isComplete: part.isComplete)
                    } else {
                        AIChatCodeBlock(title: language.isEmpty ? "コード" : language, text: code, copyID: copyID + ".\(part.id)")
                    }
                }
            }
        }
    }
}

struct AIChatCodeBlock: View {
    let title: String
    let text: String
    let copyID: String
    @State private var copied = false
    @State private var copyCount = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    copyCount += 1
                } label: {
                    Label(copied ? "コピー済み" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(title + "をコピー")
                    .accessibilityIdentifier("AI.copyCode." + copyID)
            }.foregroundStyle(AIChatStyle.muted).padding(.horizontal, 12)
            ScrollView(.horizontal) {
                AISelectableText(text: text, kind: .code(language: title))
                    .fixedSize(horizontal: true, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.background(AIChatStyle.code)
        }.background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: text) { _, _ in copied = false }
            .task(id: copyCount) {
                guard copyCount > 0 else { return }
                do {
                    try await Task.sleep(for: .seconds(2))
                    copied = false
                } catch { /* A newer copy or a removed block cancels this reset. */ }
            }
    }
}

private struct AIChatBottomKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AIChatContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
