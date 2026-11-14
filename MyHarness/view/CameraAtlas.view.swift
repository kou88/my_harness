import SwiftUI
import WebKit

struct CameraAtlasView: View {
    let page: String
    let title: String
    let open: (String, String) -> Void

    var body: some View {
        CameraAtlasWeb(page: page, open: open)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CameraAtlasWeb: UIViewControllerRepresentable {
    let page: String
    let open: (String, String) -> Void

    func makeUIViewController(context: Context) -> AtlasController { AtlasController(page: page, open: open) }
    func updateUIViewController(_ controller: AtlasController, context: Context) {}
    static func dismantleUIViewController(_ controller: AtlasController, coordinator: ()) {
        controller.disconnect()
    }
}

@MainActor
private final class AtlasController: UIViewController, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    private let page: String
    private let open: (String, String) -> Void
    private let folder = Bundle.main.url(forResource: "CameraAtlas", withExtension: "bundle")
    private let handler = "cameraAtlas"

    init(page: String, open: @escaping (String, String) -> Void) {
        self.page = page
        self.open = open
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: handler)
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.allowsLinkPreview = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        view = web
        guard let folder, var url = URLComponents(url: folder.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false) else {
            var unavailable = UIContentUnavailableConfiguration.empty()
            unavailable.text = "画角集を読み込めません"
            contentUnavailableConfiguration = unavailable
            return
        }
        url.fragment = page.isEmpty ? nil : page
        if let location = url.url { web.loadFileURL(location, allowingReadAccessTo: folder) }
    }

    private func isFile(_ url: URL?, named name: String) -> Bool {
        guard let url, url.isFileURL, let folder else { return false }
        return url.standardizedFileURL.path == folder.appendingPathComponent(name).standardizedFileURL.path
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        decisionHandler(isFile(url, named: "index.html") || isFile(url, named: "viewer.html") || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.webView === view, message.frameInfo.isMainFrame,
              isFile(message.frameInfo.request.url, named: "index.html"),
              let data = message.body as? [String: String] else { replyHandler(nil, "操作を受け付けられません"); return }
        switch data["action"] {
        case "open":
            guard page.isEmpty, let slug = data["slug"], slug.count <= 64,
                  slug.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
                  let title = data["title"], !title.isEmpty, title.count <= 50 else { replyHandler(nil, "構図が見つかりません"); return }
            replyHandler(true, nil)
            open(slug, title)
        case "copy":
            guard let text = data["text"], !text.isEmpty, text.utf8.count <= 128 else { replyHandler(nil, "コピーできません"); return }
            UIPasteboard.general.string = text
            replyHandler(true, nil)
        case "share":
            guard let folder, let name = data["name"], ["two-people.pdf", "two-people.glb"].contains(name),
                  presentedViewController == nil else { replyHandler(nil, "資料を共有できません"); return }
            let sheet = UIActivityViewController(activityItems: [folder.appendingPathComponent(name)], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.maxX - 44, y: 36, width: 1, height: 1)
            present(sheet, animated: true)
            replyHandler(true, nil)
        default:
            replyHandler(nil, "この操作には対応していません")
        }
    }

    func disconnect() {
        guard let web = viewIfLoaded as? WKWebView else { return }
        web.configuration.userContentController.removeScriptMessageHandler(forName: handler, contentWorld: .page)
        web.navigationDelegate = nil
        web.stopLoading()
    }
}
