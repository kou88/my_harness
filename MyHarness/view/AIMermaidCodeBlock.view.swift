import SwiftUI
import WebKit

struct AIMermaidCodeBlock: View {
    let text: String
    let copyID: String
    let isComplete: Bool
    @State private var showingSource = false
    @State private var copied = false
    @State private var copyCount = 0
    @State private var diagramHeight: CGFloat = 180
    @State private var renderError: String?
    @State private var showingFullscreen = false

    private var sourceIsVisible: Bool { showingSource || !isComplete || renderError != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(isComplete ? "mermaid" : "mermaid · 生成中")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if isComplete && renderError == nil {
                    Button(sourceIsVisible ? "図" : "コード") { showingSource.toggle() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(sourceIsVisible ? "Mermaidの図を表示" : "Mermaidのコードを表示")
                        .accessibilityIdentifier("AI.mermaidToggle." + copyID)
                }
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    copyCount += 1
                } label: {
                    Label(copied ? "コピー済み" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Mermaidコードをコピー")
                .accessibilityIdentifier("AI.copyCode." + copyID)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AIChatStyle.muted)
            .padding(.horizontal, 12)

            if sourceIsVisible {
                if let renderError {
                    Label(renderError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.bottom, 8)
                }
                ScrollView(.horizontal) {
                    AISelectableText(text: text, kind: .code(language: "mermaid"))
                        .fixedSize(horizontal: true, vertical: true).padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(AIChatStyle.code)
            } else {
                ZStack(alignment: .topTrailing) {
                    AIMermaidDiagramView(source: text, mode: .thumbnail, height: $diagramHeight, error: $renderError)
                        .frame(height: diagramHeight)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showingFullscreen = true }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Mermaid図を全画面表示")
                        .accessibilityHint("ダブルタップで全画面表示します")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("AI.mermaidOpen." + copyID)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AIChatStyle.muted)
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                        .padding(8)
                        .allowsHitTesting(false)
                }
                .background(AIChatStyle.code)
            }
        }
        .background(AIChatStyle.bubble, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .fullScreenCover(isPresented: $showingFullscreen) {
            AIMermaidFullscreenView(source: text)
        }
        .onChange(of: text) { _, _ in
            copied = false
            renderError = nil
        }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                copied = false
            } catch { /* A newer copy or a removed block cancels this reset. */ }
        }
    }
}

private struct AIMermaidFullscreenView: View {
    let source: String
    @Environment(\.dismiss) private var dismiss
    @State private var ignoredHeight: CGFloat = 0
    @State private var renderError: String?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let renderError {
                VStack(alignment: .leading, spacing: 12) {
                    Label(renderError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    ScrollView([.horizontal, .vertical]) {
                        Text(source)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            } else {
                AIMermaidDiagramView(source: source, mode: .fullscreen, height: $ignoredHeight, error: $renderError)
                    .accessibilityLabel("全画面のMermaid図")
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mermaid").font(.headline)
                    Text("ピンチで拡大・ドラッグで移動")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mermaid図を閉じる")
                .accessibilityIdentifier("AI.mermaidClose")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

private enum AIMermaidPresentationMode: String {
    case thumbnail
    case fullscreen
}

private struct AIMermaidDiagramView: UIViewRepresentable {
    let source: String
    let mode: AIMermaidPresentationMode
    @Binding var height: CGFloat
    @Binding var error: String?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mermaid")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.isScrollEnabled = mode == .fullscreen
        webView.scrollView.pinchGestureRecognizer?.isEnabled = mode == .fullscreen
        webView.allowsLinkPreview = false
        webView.accessibilityIdentifier = mode == .fullscreen ? "AI.mermaidFullscreen" : "AI.mermaidDiagram"
        context.coordinator.update(webView, source: source, theme: theme, mode: mode)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.scrollView.isScrollEnabled = mode == .fullscreen
        webView.scrollView.pinchGestureRecognizer?.isEnabled = mode == .fullscreen
        context.coordinator.update(webView, source: source, theme: theme, mode: mode)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaid")
        webView.navigationDelegate = nil
    }

    private var theme: String { colorScheme == .dark ? "dark" : "default" }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AIMermaidDiagramView
        private var loaded = false
        private var requestedSource = ""
        private var requestedTheme = ""
        private var requestedMode = AIMermaidPresentationMode.thumbnail
        private var renderedSource: String?
        private var renderedMode: AIMermaidPresentationMode?
        private var requestID = 0

        init(parent: AIMermaidDiagramView) { self.parent = parent }

        func update(_ webView: WKWebView, source: String, theme: String, mode: AIMermaidPresentationMode) {
            requestedSource = source
            requestedMode = mode
            if requestedTheme != theme {
                requestedTheme = theme
                loaded = false
                renderedSource = nil
                renderedMode = nil
                loadPage(webView)
            } else if loaded && (renderedSource != source || renderedMode != mode) {
                render(webView)
            }
        }

        private func loadPage(_ webView: WKWebView) {
            guard let page = Bundle.main.url(forResource: "mermaid", withExtension: "html") else {
                parent.error = "Mermaid描画資材を読み込めません"
                return
            }
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            render(webView)
        }

        private func render(_ webView: WKWebView) {
            guard loaded else { return }
            renderedSource = requestedSource
            renderedMode = requestedMode
            requestID += 1
            let currentRequest = requestID
            parent.error = nil
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "return await renderDiagram(source, requestID, theme, mode);",
                        arguments: ["source": requestedSource, "requestID": currentRequest,
                                    "theme": requestedTheme, "mode": requestedMode.rawValue],
                        contentWorld: .page
                    )
                } catch where currentRequest == requestID {
                    parent.error = "Mermaidの図を表示できません"
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaid", let payload = message.body as? [String: Any],
                  (payload["requestID"] as? NSNumber)?.intValue == requestID,
                  let status = payload["status"] as? String else { return }
            if status == "rendered", let value = payload["height"] as? NSNumber {
                if parent.mode == .thumbnail {
                    parent.height = min(max(CGFloat(value.doubleValue), 120), 444)
                }
                parent.error = nil
            } else if status == "error" {
                parent.error = "Mermaidの記法を確認してください"
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let scheme = navigationAction.request.url?.scheme else { return .cancel }
            return scheme == "file" || scheme == "about" ? .allow : .cancel
        }
    }
}
