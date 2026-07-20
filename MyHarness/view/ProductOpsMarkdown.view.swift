import SwiftUI

struct ProductOpsMarkdownView: View {
    let markdown: String

    private var blocks: [ProductOpsMarkdownBlock] {
        ProductOpsMarkdownParser.parse(markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ProductOpsMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? 2 : 18)
                .padding(.bottom, level == 1 ? 10 : 6)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

        case .unorderedItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
            .padding(.bottom, 6)

        case .orderedItem(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(number).")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 6)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)

        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(10)
            }
            .background(.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.vertical, 6)

        case .divider:
            Divider()
                .padding(.vertical, 12)
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .headline.weight(.bold)
        default: .subheadline.weight(.semibold)
        }
    }
}

private struct ProductOpsMarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedItem(String)
        case orderedItem(number: Int, text: String)
        case quote(String)
        case code(String)
        case divider
    }

    let id: Int
    let kind: Kind
}

private enum ProductOpsMarkdownParser {
    static func parse(_ markdown: String) -> [ProductOpsMarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [ProductOpsMarkdownBlock] = []
        var index = 0

        func append(_ kind: ProductOpsMarkdownBlock.Kind) {
            blocks.append(ProductOpsMarkdownBlock(id: blocks.count, kind: kind))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: trimmed) {
                append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                append(.divider)
                index += 1
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                append(.unorderedItem(item))
                index += 1
                continue
            }

            if let item = orderedItem(from: trimmed) {
                append(.orderedItem(number: item.number, text: item.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                append(.quote(String(trimmed.dropFirst(2))))
                index += 1
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || startsBlock(next) { break }
                paragraphLines.append(next)
                index += 1
            }
            append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                return (level, String(line.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private static func unorderedItem(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> (number: Int, text: String)? {
        guard let separator = line.firstIndex(of: ".") else { return nil }
        let numberText = line[..<separator]
        let textStart = line.index(after: separator)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              textStart < line.endIndex,
              line[textStart] == " ",
              let number = Int(numberText) else {
            return nil
        }
        return (number, String(line[line.index(after: textStart)...]))
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("# ")
            || line.hasPrefix("## ")
            || line.hasPrefix("### ")
            || line.hasPrefix("#### ")
            || line.hasPrefix("##### ")
            || line.hasPrefix("###### ")
            || line.hasPrefix("```")
            || line.hasPrefix("> ")
            || unorderedItem(from: line) != nil
            || orderedItem(from: line) != nil
            || line == "---"
            || line == "***"
            || line == "___"
    }
}
