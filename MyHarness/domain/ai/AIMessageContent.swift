import Foundation

/// Splits top-level Markdown fences without flattening the selectable prose around them.
enum AIMessageContent {
    struct Part: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case text(String)
            case code(language: String, text: String)
        }
        // Ordinal view identity stays stable as a streamed block grows.
        let id: Int
        let kind: Kind
    }

    static func parse(_ source: String) -> [Part] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var parts: [Part] = []
        var prose = ""
        var index = 0

        func flushProse() {
            if !prose.isEmpty { parts.append(Part(id: parts.count, kind: .text(prose))) }
            prose = ""
        }

        while index < lines.count {
            guard let fence = Fence.opening(lines[index]) else {
                prose += lines[index]
                if index < lines.count - 1 { prose += "\n" }
                index += 1
                continue
            }
            flushProse()
            index += 1
            var code = ""
            while index < lines.count && !fence.closes(lines[index]) {
                // CommonMark removes up to the opening fence's indentation, not code indentation.
                let indent = min(fence.indent, lines[index].prefix(while: { $0 == " " }).count)
                code += lines[index].dropFirst(indent)
                if index < lines.count - 1 { code += "\n" }
                index += 1
            }
            parts.append(Part(id: parts.count, kind: .code(language: fence.language, text: code)))
            if index < lines.count { index += 1 }
            // An unfinished fence intentionally exposes the code received so far.
        }
        flushProse()
        return parts
    }

    private struct Fence {
        let marker: Character
        let length: Int
        let indent: Int
        let language: String

        static func opening(_ line: Substring) -> Fence? {
            let indent = line.prefix(while: { $0 == " " }).count
            guard indent <= 3 else { return nil }
            let content = line.dropFirst(indent)
            guard let marker = content.first, marker == "`" || marker == "~" else { return nil }
            let length = content.prefix(while: { $0 == marker }).count
            guard length >= 3 else { return nil }
            let info = content.dropFirst(length)
            guard marker != "`" || !info.contains("`") else { return nil }
            // An absent info string means an explicitly unlabeled code block.
            let language = String(info.drop(while: { $0 == " " || $0 == "\t" }).prefix(while: { !$0.isWhitespace }))
            return Fence(marker: marker, length: length, indent: indent, language: language)
        }

        func closes(_ line: Substring) -> Bool {
            let indent = line.prefix(while: { $0 == " " }).count
            guard indent <= 3 else { return false }
            let content = line.dropFirst(indent)
            let count = content.prefix(while: { $0 == marker }).count
            return count >= length && content.dropFirst(count).allSatisfy { $0 == " " || $0 == "\t" }
        }
    }
}
