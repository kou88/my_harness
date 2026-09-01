import Foundation

/// Separates GFM tables from surrounding Markdown so SwiftUI can give tables
/// their own horizontally scrollable layout without flattening prose lines.
enum AIMarkdownContent {
    enum Alignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    struct Table: Equatable, Sendable {
        let headers: [String]
        let alignments: [Alignment]
        let rows: [[String]]
    }

    struct Part: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case markdown(String)
            case table(Table)
        }

        let id: Int
        let kind: Kind
    }

    static func parse(_ source: String) -> [Part] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var parts: [Part] = []
        var markdownLines: [String] = []
        var index = 0

        func append(_ kind: Part.Kind) {
            parts.append(Part(id: parts.count, kind: kind))
        }

        func flushMarkdown() {
            guard !markdownLines.isEmpty else { return }
            let markdown = markdownLines.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append(.markdown(markdown))
            }
            markdownLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            if let parsed = table(in: lines, at: index) {
                flushMarkdown()
                append(.table(parsed.table))
                index = parsed.nextIndex
            } else {
                markdownLines.append(lines[index])
                index += 1
            }
        }
        flushMarkdown()
        return parts
    }

    private static func table(in lines: [String], at index: Int) -> (table: Table, nextIndex: Int)? {
        guard index + 1 < lines.count,
              let headers = splitRow(lines[index]),
              headers.count >= 2,
              headers.contains(where: { !$0.isEmpty }),
              let delimiter = splitRow(lines[index + 1]),
              delimiter.count == headers.count else {
            return nil
        }

        let alignments = delimiter.compactMap(alignment(from:))
        guard alignments.count == headers.count else { return nil }

        var rows: [[String]] = []
        var nextIndex = index + 2
        while nextIndex < lines.count {
            let line = lines[nextIndex]
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let cells = splitRow(line) else {
                break
            }
            rows.append(normalize(cells, columnCount: headers.count))
            nextIndex += 1
        }

        return (Table(headers: headers, alignments: alignments, rows: rows), nextIndex)
    }

    /// Splits only structural pipes. Escaped pipes and pipes inside inline code stay in the cell.
    private static func splitRow(_ line: String) -> [String]? {
        let source = line.trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty else { return nil }

        var cells: [String] = []
        var cell = ""
        var foundSeparator = false
        var inlineCodeFenceLength: Int?
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)

            if character == "\\", next < source.endIndex, source[next] == "|" {
                cell.append("|")
                index = source.index(after: next)
                continue
            }
            if character == "\\", next < source.endIndex, source[next] == "`" {
                cell.append(character)
                cell.append(source[next])
                index = source.index(after: next)
                continue
            }
            if character == "`" {
                let end = source[next...].firstIndex(where: { $0 != "`" }) ?? source.endIndex
                let length = source.distance(from: index, to: end)
                cell.append(contentsOf: source[index..<end])
                if inlineCodeFenceLength == nil {
                    inlineCodeFenceLength = length
                } else if inlineCodeFenceLength == length {
                    inlineCodeFenceLength = nil
                }
                index = end
                continue
            }
            if character == "|", inlineCodeFenceLength == nil {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                foundSeparator = true
                index = next
                continue
            }

            cell.append(character)
            index = next
        }

        guard foundSeparator else { return nil }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if source.first == "|" { cells.removeFirst() }
        if cell.isEmpty, source.last == "|" { cells.removeLast() }
        return cells
    }

    private static func alignment(from source: String) -> Alignment? {
        var marker = source.trimmingCharacters(in: .whitespaces)
        let leadingColon = marker.first == ":"
        let trailingColon = marker.last == ":"
        if leadingColon { marker.removeFirst() }
        if trailingColon, !marker.isEmpty { marker.removeLast() }
        guard marker.count >= 3, marker.allSatisfy({ $0 == "-" }) else { return nil }
        if leadingColon && trailingColon { return .center }
        if trailingColon { return .trailing }
        return .leading
    }

    private static func normalize(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count == columnCount { return cells }
        if cells.count < columnCount {
            return cells + Array(repeating: "", count: columnCount - cells.count)
        }
        // GFM ignores body cells beyond the number declared by the header.
        return Array(cells.prefix(columnCount))
    }
}
