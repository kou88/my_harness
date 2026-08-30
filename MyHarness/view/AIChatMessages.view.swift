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
                LazyVStack(alignment: .leading, spacing: 36) {
                    ForEach(detail.runs) { run in AIRunMessage(run: run, state: state).id(run.id) }
                    Color.clear.frame(height: 1).id("bottom")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: AIChatBottomKey.self, value: geometry.frame(in: .named("AI.messageScroll")).maxY)
                        })
                }.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
            }
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
            .onChange(of: detail.runs.last?.lastSeq) { _, _ in
                if following && !userScrolling { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: detail.runs.count) { _, _ in following = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 30)
                Text(run.inputText).font(.system(size: 16)).lineSpacing(3).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 24))
            }.padding(.bottom, 40)
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
                    Text(trace.reasoning).font(.system(size: 14)).lineSpacing(4).foregroundStyle(AIChatStyle.muted)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(AIChatStyle.border).frame(width: 2) }
                }.padding(.bottom, 8)
            }
            ForEach(trace.tools) { tool in
                AITraceDisclosure(title: tool.name == "execute_code" ? "コード実行 · execute_code" : tool.name, icon: tool.name == "execute_code" ? "terminal" : "wrench", completed: tool.completed) {
                    VStack(alignment: .leading, spacing: 10) {
                        AIChatCodeBlock(title: tool.name == "execute_code" ? "python" : "入力", text: tool.displayArguments)
                        if tool.completed { AIChatCodeBlock(title: "結果", text: tool.displayOutput) }
                    }
                }.padding(.bottom, 8)
            }
            if !run.outputText.isEmpty { ProductOpsMarkdownView(markdown: run.outputText).padding(.top, 2) }
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
                    if let usage = trace.events.last(where: { $0.type == "usage" })?.data["usage"] { AIChatCodeBlock(title: "使用トークン", text: usage.formatted) }
                    ForEach(trace.events.filter { $0.type == "status" && $0.data["done"] == .bool(true) }) { event in
                        Text(event.text("description"))
                    }
                }.font(.caption).foregroundStyle(AIChatStyle.muted).padding(.vertical, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task(id: run.id) { await state.loadTrace(run.id) }
    }
}

private struct AITraceDisclosure<Content: View>: View {
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

private struct AIChatCodeBlock: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Button { UIPasteboard.general.string = text } label: {
                    Label("コピー", systemImage: "doc.on.doc").font(.system(size: 11))
                }.buttonStyle(.plain).accessibilityLabel(title + "をコピー")
            }.foregroundStyle(AIChatStyle.muted).padding(.horizontal, 12).padding(.vertical, 10)
            ScrollView(.horizontal) {
                Text(text).font(.system(size: 13, design: .monospaced)).lineSpacing(3).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color.black.opacity(0.22))
        }.background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AIChatBottomKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
