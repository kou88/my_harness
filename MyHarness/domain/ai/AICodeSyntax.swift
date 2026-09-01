import Foundation

/// Lightweight, deterministic tokenization for chat code blocks.
/// It preserves the source exactly and leaves unsupported languages uncolored.
enum AICodeSyntax {
    enum Kind: Equatable, Sendable {
        case plain
        case keyword
        case string
        case number
        case comment
        case type
    }

    struct Segment: Equatable, Sendable {
        let text: String
        let kind: Kind
    }

    static func segments(_ source: String, language: String) -> [Segment] {
        guard !source.isEmpty else { return [] }
        guard let profile = profile(for: language) else { return [Segment(text: source, kind: .plain)] }
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let protected = profile.protected.matches(in: source, range: fullRange)
        var result: [Segment] = []
        var location = 0

        for match in protected {
            appendTokens(source, range: NSRange(location: location, length: match.range.location - location), profile: profile, to: &result)
            let kind: Kind = match.range(withName: "comment").location == NSNotFound ? .string : .comment
            append(source, range: match.range, kind: kind, to: &result)
            location = NSMaxRange(match.range)
        }
        appendTokens(source, range: NSRange(location: location, length: fullRange.length - location), profile: profile, to: &result)
        return result
    }

    static func normalizedLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "js": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "sh", "zsh", "shell": return "bash"
        case "yml": return "yaml"
        case "rs": return "rust"
        case "kt": return "kotlin"
        case "c++": return "cpp"
        case "cs": return "csharp"
        case "html": return "xml"
        default: return language.lowercased()
        }
    }

    private struct Profile {
        let keywords: Set<String>
        let protected: NSRegularExpression
        let tokens: NSRegularExpression

        init(keywords: String, lineComments: [String], blockComments: [String], backticks: Bool, tripleQuotes: Bool) {
            self.keywords = Set(keywords.split(separator: " ").map(String.init))
            var comments = blockComments + lineComments.map { NSRegularExpression.escapedPattern(for: $0) + "[^\\n]*" }
            if comments.isEmpty { comments = ["(?!)"] }
            var strings = [#"\"(?:\\.|[^\"\\])*\""#, #"'(?:\\.|[^'\\])*'"#]
            if backticks { strings.append(#"`(?:\\.|[^`\\])*`"#) }
            if tripleQuotes { strings.insert(#"\"\"\"[\s\S]*?\"\"\""#, at: 0); strings.insert("'''[\\s\\S]*?'''", at: 1) }
            let protectedPattern = "(?<comment>" + comments.joined(separator: "|") + ")|(?<string>" + strings.joined(separator: "|") + ")"
            protected = try! NSRegularExpression(pattern: protectedPattern)
            let escapedKeywords = self.keywords.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            let keywordPattern = escapedKeywords.isEmpty ? "(?!)" : "\\b(?:" + escapedKeywords + ")\\b"
            tokens = try! NSRegularExpression(pattern: keywordPattern + #"|\b(?:0[xX][0-9A-Fa-f]+|\d+(?:\.\d+)?)\b|\b[A-Z][A-Za-z0-9_]*\b"#)
        }
    }

    private static let swift = Profile(
        keywords: "actor any as associatedtype async await break case catch class continue convenience copy consuming default defer deinit didSet distributed do dynamic each else enum extension fallthrough false fileprivate final for borrowing func get guard if import indirect init in infix inout internal is isolated lazy let macro mutating nonisolated nonmutating nil open operator optional override package postfix precedencegroup prefix private protocol public repeat required rethrows return self sending set some static struct subscript super switch throws true try typealias var weak where while willSet",
        lineComments: ["//"], blockComments: [#"/\*[\s\S]*?\*/"#], backticks: false, tripleQuotes: true
    )
    private static let python = Profile(
        keywords: "and as assert async await break case class continue def del elif else except False finally for from global if import in is lambda match None nonlocal not or pass raise return True try while with yield",
        lineComments: ["#"], blockComments: [], backticks: false, tripleQuotes: true
    )
    private static let javascript = Profile(
        keywords: "as async await break case catch class const continue debugger default delete do else export extends false finally for from function get if implements import in instanceof interface let new null of package private protected public return set static super switch this throw true try typeof undefined var void while with yield",
        lineComments: ["//"], blockComments: [#"/\*[\s\S]*?\*/"#], backticks: true, tripleQuotes: false
    )
    private static let shell = Profile(
        keywords: "case do done elif else esac export fi for function if in local readonly return set shift then time trap until while",
        lineComments: ["#"], blockComments: [], backticks: true, tripleQuotes: false
    )
    private static let sql = Profile(
        keywords: "ADD ALL ALTER AND ANY AS ASC BEGIN BETWEEN BY CASE CHECK COLUMN COMMIT CONSTRAINT CREATE CROSS DATABASE DEFAULT DELETE DESC DISTINCT DROP ELSE END EXISTS FALSE FOREIGN FROM FULL GRANT GROUP HAVING IF IN INDEX INNER INSERT INTO IS JOIN KEY LEFT LIKE LIMIT NOT NULL ON OR ORDER OUTER PRIMARY REFERENCES RIGHT ROLLBACK SELECT SET TABLE THEN TRUE UNION UNIQUE UPDATE VALUES VIEW WHEN WHERE WITH",
        lineComments: ["--"], blockComments: [#"/\*[\s\S]*?\*/"#], backticks: true, tripleQuotes: false
    )
    private static let cFamily = Profile(
        keywords: "abstract as async await bool break byte case catch char class const continue decimal default delegate do double else enum event explicit export extends extern false final finally fixed float for foreach friend func goto if implements import in inline int interface internal is let lock long namespace native new null object operator out override package params private protected protocol public readonly ref return sealed short signed sizeof static string struct subscript super switch synchronized template this throw throws trait true try typealias typedef typeof uint ulong unchecked unsafe ushort using var virtual void volatile where while",
        lineComments: ["//"], blockComments: [#"/\*[\s\S]*?\*/"#], backticks: false, tripleQuotes: false
    )
    private static let rust = Profile(
        keywords: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while",
        lineComments: ["//"], blockComments: [#"/\*[\s\S]*?\*/"#], backticks: false, tripleQuotes: false
    )
    private static let go = Profile(
        keywords: "break case chan const continue default defer else fallthrough false for func go goto if import interface map nil package range return select struct switch true type var",
        lineComments: ["//"], blockComments: [#"/\*[\s\S]*?\*/"#], backticks: true, tripleQuotes: false
    )
    private static let data = Profile(
        keywords: "false null true",
        lineComments: [], blockComments: [], backticks: false, tripleQuotes: false
    )
    private static let yaml = Profile(
        keywords: "false no null off on true yes",
        lineComments: ["#"], blockComments: [], backticks: false, tripleQuotes: false
    )
    private static let xml = Profile(
        keywords: "",
        lineComments: [], blockComments: [#"<!--[\s\S]*?-->"#], backticks: false, tripleQuotes: false
    )

    private static func profile(for language: String) -> Profile? {
        switch normalizedLanguage(language) {
        case "swift": return swift
        case "python": return python
        case "javascript", "typescript": return javascript
        case "bash": return shell
        case "sql": return sql
        case "java", "kotlin", "c", "cpp", "csharp": return cFamily
        case "rust": return rust
        case "go": return go
        case "json": return data
        case "yaml": return yaml
        case "xml": return xml
        default: return nil
        }
    }

    private static func appendTokens(_ source: String, range: NSRange, profile: Profile, to result: inout [Segment]) {
        guard range.length > 0 else { return }
        var location = range.location
        for match in profile.tokens.matches(in: source, range: range) {
            append(source, range: NSRange(location: location, length: match.range.location - location), kind: .plain, to: &result)
            let value = substring(source, range: match.range)
            let kind: Kind
            if profile.keywords.contains(value) { kind = .keyword }
            else if value.first?.isNumber == true { kind = .number }
            else { kind = .type }
            append(value, kind: kind, to: &result)
            location = NSMaxRange(match.range)
        }
        append(source, range: NSRange(location: location, length: NSMaxRange(range) - location), kind: .plain, to: &result)
    }

    private static func append(_ source: String, range: NSRange, kind: Kind, to result: inout [Segment]) {
        guard range.length > 0 else { return }
        append(substring(source, range: range), kind: kind, to: &result)
    }

    private static func append(_ text: String, kind: Kind, to result: inout [Segment]) {
        guard !text.isEmpty else { return }
        if result.last?.kind == kind {
            let previous = result.removeLast()
            result.append(Segment(text: previous.text + text, kind: kind))
        } else {
            result.append(Segment(text: text, kind: kind))
        }
    }

    private static func substring(_ source: String, range: NSRange) -> String {
        guard let swiftRange = Range(range, in: source) else { return "" }
        return String(source[swiftRange])
    }
}
