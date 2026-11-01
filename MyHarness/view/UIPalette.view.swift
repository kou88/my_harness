import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct UIPaletteView: View {
    var body: some View {
        PaletteWebView()
            .navigationTitle("UI図鑑")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PaletteWebView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PaletteController { PaletteController() }
    func updateUIViewController(_ controller: PaletteController, context: Context) {}
    static func dismantleUIViewController(_ controller: PaletteController, coordinator: ()) {
        controller.disconnect()
    }
}

@MainActor
private final class PaletteController: UIViewController, WKScriptMessageHandlerWithReply, WKNavigationDelegate, UIDocumentPickerDelegate {
    private typealias Reply = (Any?, String?) -> Void
    private enum Operation {
        case importing
        case exporting(directory: URL)
    }
    private static let origin = URL(string: "https://ui-palette.invalid/")!
    private static let storeID = UUID(uuidString: "dd07d401-5ec1-466c-a735-ef543c468d1c")!
    private let bridge = "paletteFiles"
    private var pending: (operation: Operation, reply: Reply)?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeID)
        let scripts = configuration.userContentController
        scripts.addScriptMessageHandler(self, contentWorld: .page, name: bridge)
        scripts.addUserScript(WKUserScript(
            source: "window.name = 'ui-palette:ios-device'",
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.allowsLinkPreview = false
        view = web
        do {
            guard let resource = Bundle.main.url(forResource: "UIPaletteStudio", withExtension: "html") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let html = try String(contentsOf: resource, encoding: .utf8)
            // バンドル内の文書に固定オリジンを与え、アプリ更新後も同じIndexedDBを使う。
            web.loadHTMLString(html, baseURL: Self.origin)
        } catch {
            var unavailable = UIContentUnavailableConfiguration.empty()
            unavailable.text = "UI図鑑を読み込めません"
            unavailable.secondaryText = error.localizedDescription
            contentUnavailableConfiguration = unavailable
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        decisionHandler(url == Self.origin || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.webView === view, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == Self.origin.host,
              let request = message.body as? [String: String] else {
            replyHandler(nil, "ファイル操作を受け付けられません。")
            return
        }
        guard pending == nil, presentedViewController == nil else {
            replyHandler(nil, "現在のファイル操作を完了してください。")
            return
        }
        let picker: UIDocumentPickerViewController
        switch request["action"] {
        case "copyName":
            guard let text = request["text"], !text.isEmpty, text.utf8.count <= 256 else {
                replyHandler(nil, "部品名をコピーできません。")
                return
            }
            UIPasteboard.general.string = text
            replyHandler(true, nil)
            return
        case "import":
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            pending = (.importing, replyHandler)
        case "export":
            guard let name = request["filename"], !name.isEmpty, name.utf8.count < 255,
                  !name.contains("/"), !name.contains("\\"), !name.hasPrefix("."),
                  let mime = request["mime"], let encoded = request["data"], encoded.utf8.count <= 8_000_000,
                  (mime == "application/json" && name.hasSuffix(".json")) || (mime == "image/png" && name.hasSuffix(".png")),
                  let bytes = Data(base64Encoded: encoded) else {
                replyHandler(nil, "書き出すファイルの形式を確認してください。")
                return
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let url = directory.appendingPathComponent(name)
                try bytes.write(to: url, options: .atomic)
                picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                pending = (.exporting(directory: directory), replyHandler)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                replyHandler(nil, error.localizedDescription)
                return
            }
        default:
            replyHandler(nil, "不明なファイル操作です。")
            return
        }
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let pending, let url = urls.first else { finish(NSNull(), nil); return }
        switch pending.operation {
        case .exporting:
            finish(true, nil)
        case .importing:
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                let data = try input.read(upToCount: 1_000_001) ?? Data()
                guard data.count <= 1_000_000, let json = String(data: data, encoding: .utf8) else {
                    finish(nil, "1 MB以下のUTF-8 JSONを選んでください。")
                    return
                }
                finish(json, nil)
            } catch { finish(nil, error.localizedDescription) }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(NSNull(), nil) }

    private func finish(_ value: Any?, _ error: String?) {
        guard let action = pending else { return }
        pending = nil
        if case .exporting(let directory) = action.operation {
            try? FileManager.default.removeItem(at: directory)
        }
        action.reply(value, error)
    }

    func disconnect() {
        (viewIfLoaded as? WKWebView)?.configuration.userContentController.removeScriptMessageHandler(forName: bridge, contentWorld: .page)
        finish(NSNull(), nil)
    }
}
