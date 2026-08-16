import SwiftUI
import WebKit

enum KonomiTVConfiguration {
    static var serverURL: URL {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "KonomiTVBaseURL") as? String,
              let url = URL(string: rawValue),
              url.scheme == "https",
              url.host != nil else {
            fatalError("MyHarnessInfo.plist の KonomiTVBaseURL に有効な HTTPS URL が必要です。")
        }
        return url
    }
}

struct TelevisionView: View {
    let serverURL: URL

    @Environment(\.openURL) private var openURL
    @State private var reloadGeneration = 0
    @State private var isLoading = true
    @State private var failureMessage: String?

    var body: some View {
        ZStack {
            KonomiTVWebView(
                serverURL: serverURL,
                reloadGeneration: reloadGeneration,
                isLoading: $isLoading,
                failureMessage: $failureMessage
            )
            .ignoresSafeArea(edges: .bottom)

            if let failureMessage {
                connectionError(message: failureMessage)
            }
        }
        .overlay(alignment: .top) {
            if isLoading && failureMessage == nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityLabel("テレビを読み込んでいます")
            }
        }
        .navigationTitle("テレビ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("再読み込み", systemImage: "arrow.clockwise") {
                    retry()
                }

                Button("Safariで開く", systemImage: "safari") {
                    openURL(serverURL)
                }
            }
        }
    }

    private func connectionError(message: String) -> some View {
        ContentUnavailableView {
            Label("テレビに接続できません", systemImage: "tv.slash")
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button("再試行") {
                    retry()
                }
                .buttonStyle(.borderedProminent)

                Button("Safariで開く") {
                    openURL(serverURL)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.regularMaterial)
    }

    private func retry() {
        failureMessage = nil
        isLoading = true
        reloadGeneration += 1
    }
}

private struct KonomiTVWebView: UIViewRepresentable {
    let serverURL: URL
    let reloadGeneration: Int
    @Binding var isLoading: Bool
    @Binding var failureMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.loadedServerURL = serverURL
        context.coordinator.handledReloadGeneration = reloadGeneration
        webView.load(URLRequest(url: serverURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.loadedServerURL != serverURL {
            context.coordinator.loadedServerURL = serverURL
            context.coordinator.handledReloadGeneration = reloadGeneration
            webView.load(URLRequest(url: serverURL))
            return
        }

        guard context.coordinator.handledReloadGeneration != reloadGeneration else { return }
        context.coordinator.handledReloadGeneration = reloadGeneration

        if webView.url == nil {
            webView.load(URLRequest(url: serverURL))
        } else {
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: KonomiTVWebView
        var loadedServerURL: URL?
        var handledReloadGeneration = 0

        init(parent: KonomiTVWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            parent.isLoading = true
            parent.failureMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            parent.isLoading = false
            parent.failureMessage = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: any Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func report(_ error: any Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }

            parent.isLoading = false
            parent.failureMessage = "同じWi-Fiに接続してから再試行してください。\n\(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        TelevisionView(serverURL: URL(string: "https://192-168-11-54.local.konomi.tv:7000/")!)
    }
}
