import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let iconView = UIImageView(image: UIImage(systemName: "square.and.arrow.down"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let progressView = UIActivityIndicatorView(style: .medium)
    private let finishButton = UIButton(type: .system)
    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        Task { await captureSharedCandidate() }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .medium)

        titleLabel.text = "取り込み候補に追加"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        messageLabel.text = "Xの共有内容を確認しています"
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        progressView.startAnimating()

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = "閉じる"
        buttonConfiguration.cornerStyle = .large
        finishButton.configuration = buttonConfiguration
        finishButton.isHidden = true
        finishButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            titleLabel,
            messageLabel,
            progressView,
            finishButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            finishButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    private func captureSharedCandidate() async {
        do {
            let sharedContent = try await loadSharedContent()
            let candidate = try SharedXImportCandidate.make(
                id: UUID().uuidString.lowercased(),
                sharedURL: sharedContent.url.absoluteString,
                sharedText: sharedContent.text,
                createdAt: Date()
            )
            let repository = try SharedXImportCandidateRepository(
                appGroupIdentifier: "group.com.kou888.myharness"
            )
            try repository.save(candidate)

            progressView.stopAnimating()
            progressView.isHidden = true
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            iconView.tintColor = .systemGreen
            titleLabel.text = "候補に追加しました"
            messageLabel.text = "my harnessの記事タブで内容を確認してから取り込めます。"
            finishButton.isHidden = false
        } catch {
            progressView.stopAnimating()
            progressView.isHidden = true
            iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            iconView.tintColor = .systemOrange
            titleLabel.text = "追加できませんでした"
            messageLabel.text = error.localizedDescription
            finishButton.isHidden = false
        }
    }

    private func loadSharedContent() async throws -> (url: URL, text: String?) {
        let attachments = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        var sharedText: String?
        for attachment in attachments where attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await loadText(from: attachment) {
                sharedText = text
                break
            }
        }

        for attachment in attachments where attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try await loadURL(from: attachment) {
                return (url, sharedText)
            }
        }

        if let sharedText, let url = firstURL(in: sharedText) {
            return (url, sharedText)
        }

        throw ShareImportError.missingXURL
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let value = item as? String {
                    continuation.resume(returning: URL(string: value))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let text = item as? NSString {
                    continuation.resume(returning: text as String)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    @objc
    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

private enum ShareImportError: LocalizedError {
    case missingXURL

    var errorDescription: String? {
        switch self {
        case .missingXURL:
            return "Xの投稿URLを取得できませんでした。Xの共有ボタンからもう一度お試しください。"
        }
    }
}
