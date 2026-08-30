import SwiftUI
import UIKit

/// One native text selection surface per message, including across Markdown paragraphs.
struct AISelectableText: UIViewRepresentable {
    enum Kind { case message, markdown, reasoning, code }
    let text: String
    let kind: Kind

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [.foregroundColor: UIColor.link]
        view.accessibilityIdentifier = "AI.selectableText"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let content = attributedText
        guard !view.attributedText.isEqual(to: content) else { return }
        let selected = view.selectedRange
        view.attributedText = content
        // Appending streamed text must not discard a user's existing selection.
        if selected.length > 0, NSMaxRange(selected) <= content.length { view.selectedRange = selected }
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let natural = ceil(uiView.attributedText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).width) + 1
        // SwiftUI also probes with zero/infinite widths during navigation layout.
        // Never ask UITextView to wrap a streaming message into a zero-width column.
        if let proposed = proposal.width, proposed <= 0 { return .zero }
        let available: CGFloat
        if let proposed = proposal.width, proposed.isFinite { available = proposed }
        else { available = max(1, natural) }
        let width = kind == .message || kind == .code ? min(available, max(1, natural)) : available
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    private var attributedText: NSAttributedString {
        switch kind {
        case .message: return plain(text, font: scaled(16), color: .label)
        case .reasoning: return plain(text, font: scaled(14), color: UIColor(AIChatStyle.muted))
        case .code: return plain(text, font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular)), color: .label)
        case .markdown: return markdown
        }
    }

    private func scaled(_ size: CGFloat) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size))
    }

    private func plain(_ value: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
        return NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private var markdown: NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for block in ProductOpsMarkdownParser.parse(text) {
            let content: NSAttributedString
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3; paragraph.paragraphSpacing = 8
            switch block.kind {
            case .heading(let level, let value):
                let font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: level == 1 ? 22 : 17, weight: .bold))
                content = inline(value, font: font, color: .label)
                paragraph.paragraphSpacingBefore = result.length == 0 ? 0 : 12
            case .paragraph(let value): content = inline(value, font: scaled(17), color: .label)
            case .unorderedItem(let value):
                content = inline("• " + value, font: scaled(17), color: .label)
                paragraph.headIndent = 18; paragraph.paragraphSpacing = 6
            case .orderedItem(let number, let value):
                content = inline("\(number). " + value, font: scaled(17), color: .label)
                paragraph.headIndent = 24; paragraph.paragraphSpacing = 6
            case .quote(let value):
                content = inline(value, font: scaled(17), color: .secondaryLabel)
                paragraph.firstLineHeadIndent = 12; paragraph.headIndent = 12
            case .code(let value):
                content = NSAttributedString(string: value, attributes: [
                    .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular)),
                    .foregroundColor: UIColor.label, .backgroundColor: UIColor(AIChatStyle.code)
                ])
                paragraph.paragraphSpacing = 12
            case .divider: content = plain("────────", font: scaled(14), color: .separator)
            }
            let rendered = NSMutableAttributedString(attributedString: content)
            rendered.append(NSAttributedString(string: "\n"))
            rendered.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: rendered.length))
            result.append(rendered)
        }
        if result.length > 0 { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        return result
    }

    private func inline(_ source: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else { return plain(source, font: font, color: color) }
        let result = NSMutableAttributedString(string: "")
        for run in parsed.runs {
            var runFont = font
            var traits = font.fontDescriptor.symbolicTraits
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { traits.insert(.traitBold) }
            if run.inlinePresentationIntent?.contains(.emphasized) == true { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { runFont = UIFont(descriptor: descriptor, size: font.pointSize) }
            if run.inlinePresentationIntent?.contains(.code) == true { runFont = .monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular) }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
            if let link = run.link { attributes[.link] = link }
            if run.inlinePresentationIntent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: String(parsed.characters[run.range]), attributes: attributes))
        }
        return result
    }
}
