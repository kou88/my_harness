import SwiftUI
import UIKit

// Isolated test host: real chat views/state, in-memory transport, no production login or GPU.
enum AppTab { case today, nextActions, articles, ai, television }
enum AppRoute { case aiConversation(id: String) }
@MainActor @Observable final class AppRouter {
    var aiPath: [AppRoute] = []
    var selectedTab = AppTab.ai
}

@main struct ChatUIRegressionApp: App {
    var body: some Scene { WindowGroup { ChatUIRegressionView() } }
}

@MainActor private struct ChatUIRegressionView: View {
    @State private var router = AppRouter()
    @State private var state: AIChatState
    private let api: AIAPIClient
    private let conversationId: String
    private let runId: String
    private let otherId: String
    private let codingId: String
    private let renderingId: String
    @State private var shown = true
    @State private var result = "長文・生成中の再表示テスト"

    init() {
        let api = AIAPIClient()
        let id = UUID().uuidString.lowercased()
        let activeId = UUID().uuidString.lowercased()
        let runs = (0..<12).map { index in
            let paragraphs = (0..<(index == 11 ? 70 : 8)).map { "段落\($0): 生成中に会話を開き直しても、回答が画面内に表示されることを確認します。" }.joined(separator: "\n\n")
            return AIRun(id: index == 11 ? activeId : UUID().uuidString.lowercased(), conversationId: id,
                hostId: "host", modelId: api.model.id, model: "表示確認モデル", settings: api.model.initialSettings, delivery: .changes,
                inputText: "再表示テスト \(index + 1)",
                outputText: paragraphs,
                status: index == 11 ? "running" : "completed", cancelRequested: false, lastSeq: 0,
                error: "", responseId: "", previousResponseId: "", createdAt: "test", updatedAt: "test")
        }
        api.details[id] = AIConversationDetail(id: id, title: "生成中の長文", context: .hermes, createdAt: "test", updatedAt: "test", runs: runs)
        let other = UUID().uuidString.lowercased()
        api.details[other] = AIConversationDetail(id: other, title: "別の会話", context: .hermes, createdAt: "test", updatedAt: "test", runs: [])
        let coding = UUID().uuidString.lowercased(), codingRun = UUID().uuidString.lowercased()
        let repo = AIRepository(id: UUID().uuidString.lowercased(), hostId: "host", hostName: "PC-02", online: true, repository: "kou88/my_api", branches: ["prod", "develop"], defaultBranch: "prod")
        api.repositoryValues = [repo]
        api.details[coding] = AIConversationDetail(id: coding, title: "APIのテストを追加", context: .opencode(AICodingContext(repositoryId: repo.id, repository: repo.repository, hostId: "host", baseBranch: "develop", workBranch: "agent/" + coding)), createdAt: "test", updatedAt: "test", runs: [
            AIRun(id: codingRun, conversationId: coding, hostId: "host", modelId: api.model.id, model: "表示確認モデル", settings: api.model.initialSettings, delivery: .draftPR, inputText: "入力の検証を追加してDraft PRを作って", outputText: "入力の検証とテストを追加しました。確認が必要な操作があります。", status: "running", cancelRequested: false, lastSeq: 0, error: "", responseId: "", previousResponseId: "", createdAt: "test", updatedAt: "test")])
        api.requestValues[codingRun] = [AIRequest(id: UUID().uuidString.lowercased(), runId: codingRun, kind: "permission", payload: ["permission": .string("bash"), "patterns": .array([.string("rm -rf temporary-build")])], status: "pending", createdAt: "test", updatedAt: "test"),
            AIRequest(id: UUID().uuidString.lowercased(), runId: codingRun, kind: "question", payload: ["questions": .array([.object(["header": .string("対象"), "question": .string("どちらの入力を検証しますか？"), "options": .array([.object(["label": .string("名前"), "description": .string("空の名前を拒否する")]), .object(["label": .string("メール"), "description": .string("メール形式を検証する")])]), "multiple": .bool(false), "custom": .bool(true)])])], status: "pending", createdAt: "test", updatedAt: "test")]
        try! api.emit(codingRun, type: "work.diff", data: ["files": .array([.string("src/input.ts")]), "patch": .string("--- a/src/input.ts\n+++ b/src/input.ts\n@@ -1 +1 @@\n-return input\n+return validate(input)\n"), "truncated": .bool(false)])
        let rendering = UUID().uuidString.lowercased(), renderingRun = UUID().uuidString.lowercased()
        api.details[rendering] = AIConversationDetail(id: rendering, title: "コードとMermaid", context: .hermes, createdAt: "test", updatedAt: "test", runs: [
            AIRun(id: renderingRun, conversationId: rendering, hostId: "host", modelId: api.model.id, model: "表示確認モデル", settings: api.model.initialSettings, delivery: .changes,
                inputText: "コードと図を表示して", outputText: """
                Swiftコードは言語別に色分けします。

                ```swift
                struct Greeting {
                    let message = "こんにちは"
                }
                ```

                Mermaidは図と元コードを切り替えられます。

                ```mermaid
                flowchart LR
                    A[MyHarness] --> B[Mermaid]
                    B --> C[図を表示]
                ```
                """, status: "completed", cancelRequested: false, lastSeq: 0, error: "", responseId: "", previousResponseId: "", createdAt: "test", updatedAt: "test")])
        codingId = coding
        renderingId = rendering
        self.api = api; conversationId = id; runId = activeId
        otherId = other
        _state = State(initialValue: AIChatState(apiClient: api, authSession: CognitoAuthSession(), configurationErrorMessage: nil))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(result).font(.caption)
                Spacer()
                Button("コード") { router.aiPath = [.aiConversation(id: codingId)] }
                Button("追記") {
                    try? api.emit(runId, type: "text.delta", data: ["text": .string("\n\n手動追加: 過去の文を読んでいる間はスクロール位置を保持します。")])
                }
                Button("開き直す") { shown.toggle() }
            }.padding(8)
            // Match AppRoot: keep the tab's NavigationStack while replacing its screen.
            NavigationStack {
                if shown { AIConversationListView(state: state) }
                else { Text("別画面").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.environment(router)
        }
        .task {
            // Simulator launch may run app tasks before its foreground window is ready.
            // Test navigation only after UIKit has an active scene, like a user can.
            for _ in 0..<50 {
                if UIApplication.shared.applicationState == .active,
                   UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).contains(where: \.isKeyWindow) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            await state.loadList(); state.choose(api.model)
            router.aiPath = [.aiConversation(id: conversationId)]
            try? await Task.sleep(for: .seconds(1))
            var failures = 0
            for index in 0..<8 {
                if index % 2 == 0 { shown = false }
                else { router.aiPath = [.aiConversation(id: otherId)] }
                try? await Task.sleep(for: .milliseconds(120))
                try? api.emit(runId, type: "text.delta", data: ["text": .string("\n\n追加の回答 \(index): 画面を開き直した後の表示を確認しています。")])
                shown = true
                router.aiPath = [.aiConversation(id: conversationId)]
                try? await Task.sleep(for: .milliseconds(600))
                if !checkVisibleText("reopen-\(index)") { failures += 1 }
                for _ in 0..<4 {
                    try? api.emit(runId, type: "text.delta", data: ["text": .string(" ストリームの追加テキスト。")])
                    try? await Task.sleep(for: .milliseconds(70))
                }
                if !checkVisibleText("stream-\(index)") { failures += 1 }
            }
            result = failures == 0 ? "PASS: 再表示・生成中 16回" : "FAIL: 表示位置 \(failures)回"
            print("CHAT_UI_REGRESSION \(result)")
            router.aiPath = [.aiConversation(id: renderingId)]
        }
    }

    private func checkVisibleText(_ label: String) -> Bool {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let views = windows.flatMap { descendants($0) }
        let scrolls = views.compactMap { $0 as? UIScrollView }.filter { !($0 is UITextView) && $0.bounds.height > 200 }
        let texts = views.compactMap { $0 as? UITextView }.filter { !$0.isEditable && !$0.text.isEmpty }
        let visible = texts.contains { text in
            scrolls.contains { scroll in
                text.isDescendant(of: scroll) && scroll.bounds.intersection(text.convert(text.bounds, to: scroll)).height > 10
            }
        }
        let latestVisible = texts.contains { text in
            guard text.text.hasPrefix("段落0:"), text.text.contains("段落69:") else { return false }
            return scrolls.contains { scroll in
                let frame = text.convert(text.bounds, to: scroll)
                return text.isDescendant(of: scroll) && frame.maxY > scroll.bounds.minY && frame.maxY <= scroll.bounds.maxY + 1
            }
        }
        let dimensions = scrolls.map { "offset=\(Int($0.contentOffset.y)) content=\(Int($0.contentSize.height)) viewport=\(Int($0.bounds.height))" }.joined(separator: "; ")
        print("CHAT_UI_FRAME \(label) visible=\(visible) latest=\(latestVisible) texts=\(texts.count) active=\(UIApplication.shared.applicationState.rawValue) loaded=\(state.detail?.runs.count ?? -1) \(dimensions)")
        return visible && latestVisible
    }
}
