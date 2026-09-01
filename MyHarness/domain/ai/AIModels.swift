import Foundation

enum AIHarness: String, Codable, CaseIterable, Identifiable {
    case hermes, opencode
    var id: String { rawValue }
    var name: String { self == .hermes ? "Hermes" : "OpenCode" }
    var symbol: String { self == .hermes ? "sparkles" : "chevron.left.forwardslash.chevron.right" }
}
enum AIDelivery: String, Codable, CaseIterable, Identifiable {
    case changes, draftPR = "draft_pr"
    var id: String { rawValue }
    var name: String { self == .changes ? "変更まで" : "Draft PRまで" }
}
struct AIRepository: Codable, Identifiable, Hashable {
    let id: String
    let hostId: String
    let hostName: String
    let online: Bool
    let repository: String
    let branches: [String]
    let defaultBranch: String
}
struct AICodingContext: Codable, Hashable {
    let repositoryId: String
    let repository: String
    let hostId: String
    let baseBranch: String
    let workBranch: String
}
enum AIContext: Codable, Hashable {
    case hermes
    case opencode(AICodingContext)
    var harness: AIHarness { if case .hermes = self { return .hermes }; return .opencode }
    private enum Keys: String, CodingKey { case harness }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(AIHarness.self, forKey: .harness) {
        case .hermes: self = .hermes
        case .opencode: self = .opencode(try AICodingContext(from: decoder))
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(harness, forKey: .harness)
        if case .opencode(let value) = self { try value.encode(to: encoder) }
    }
}
enum AIContextInput: Encodable {
    case hermes
    case opencode(repositoryId: String, baseBranch: String)
    private enum Keys: String, CodingKey { case harness, repositoryId, baseBranch }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .hermes: try container.encode("hermes", forKey: .harness)
        case .opencode(let id, let branch):
            try container.encode("opencode", forKey: .harness)
            try container.encode(id, forKey: .repositoryId)
            try container.encode(branch, forKey: .baseBranch)
        }
    }
}
enum AIRepositorySelection {
    case unselected
    case selected(AIRepository, branch: String)
}
struct AIRequest: Decodable, Identifiable {
    let id: String
    let runId: String
    let kind: String
    let payload: [String: AIJSON]
    let status: String
    let createdAt: String
    let updatedAt: String
}
enum AIReply: Encodable {
    case permission(allow: Bool)
    case question(answers: [[String]], rejected: Bool)
    private enum Keys: String, CodingKey { case kind, allow, answers, rejected }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .permission(let allow):
            try container.encode("permission", forKey: .kind); try container.encode(allow, forKey: .allow)
        case .question(let answers, let rejected):
            try container.encode("question", forKey: .kind); try container.encode(answers, forKey: .answers); try container.encode(rejected, forKey: .rejected)
        }
    }
}

struct AISharing: Codable, Equatable {
    var enabled: Bool
    var modelId: String
    var contextLength: Int
    var maxConcurrentRuns: Int
    var revision: Int

    var capacityIsValid: Bool {
        (1...8).contains(maxConcurrentRuns)
            && [8192, 16384, 32768, 65536, 131072, 262144].contains(contextLength)
            && contextLength <= 262144 / maxConcurrentRuns
    }
}

struct AISettings: Codable, Hashable {
    var contextLength: Int
    var maxOutputTokens: Int
    var reasoningEffort: String
}
enum AIInputModality: String, Codable, Hashable {
    case text, image, video
}

struct AIModel: Codable, Identifiable, Hashable {
    let id: String
    let hostId: String
    let hostName: String
    let model: String
    let name: String
    let online: Bool
    let contextLengths: [Int]
    let maxOutputTokens: Int
    let reasoningEfforts: [String]
    let reasoningBudgets: [String: Int]
    let initialSettings: AISettings
    let inputModalities: [AIInputModality]

    func accepts(_ modality: AIInputModality) -> Bool { inputModalities.contains(modality) }

    func accepts(_ settings: AISettings) -> Bool {
        guard let budget = reasoningBudgets[settings.reasoningEffort] else { return false }
        return contextLengths.contains(settings.contextLength)
            && reasoningEfforts.contains(settings.reasoningEffort)
            && settings.maxOutputTokens >= budget + 256
            && settings.maxOutputTokens <= maxOutputTokens
            && settings.maxOutputTokens < settings.contextLength
    }
}

enum AIAttachmentKind: String, Codable, Hashable {
    case image
    case videoFrame = "video_frame"
}

struct AIAttachment: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let kind: AIAttachmentKind
    let groupId: String
    let fileName: String
    let contentType: String
    let byteSize: Int
    let frameIndex: Int
    let frameCount: Int
    let createdAt: String
}

struct AIComposerAttachment: Identifiable, Hashable {
    let id: String
    let kind: AIAttachmentKind
    let groupId: String
    let fileName: String
    let contentType: String
    let frameIndex: Int
    let frameCount: Int
    let data: Data

    var modality: AIInputModality { kind == .image ? .image : .video }
}

struct AIConversation: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let context: AIContext
    let createdAt: String
    var updatedAt: String
}

struct AIConversationDetail: Codable, Identifiable {
    let id: String
    var title: String
    let context: AIContext
    let createdAt: String
    var updatedAt: String
    var runs: [AIRun]
}

struct AIRun: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let hostId: String
    let modelId: String
    let model: String
    let settings: AISettings
    let delivery: AIDelivery
    let inputText: String
    let attachments: [AIAttachment]
    var outputText: String
    var status: String
    var cancelRequested: Bool
    var lastSeq: Int
    var error: String
    var responseId: String
    let previousResponseId: String
    let createdAt: String
    var updatedAt: String

    var isActive: Bool { status == "queued" || status == "running" }
    mutating func apply(_ event: AIEvent) throws {
        guard event.seq > lastSeq else { return }
        guard event.seq == lastSeq + 1 else { throw AIContractError.sequenceGap }
        switch event.type {
        case "run.started": status = "running"
        case "text.delta": outputText += try event.requiredText("text")
        case "run.completed":
            status = "completed"
            responseId = try event.requiredText("responseId")
        case "run.failed": status = "failed"; error = try event.requiredText("message")
        case "run.cancelled": status = "cancelled"
        default: break
        }
        lastSeq = event.seq
        updatedAt = event.createdAt
    }
}

struct AIStreamingPresentation: Equatable {
    private(set) var displayed: String
    private(set) var target: String
    private var charactersPerTick = 0

    init(text: String) {
        displayed = text
        target = text
    }

    var needsAdvance: Bool { displayed != target }

    mutating func receive(_ text: String) {
        guard text.hasPrefix(displayed) else {
            displayed = text
            target = text
            charactersPerTick = 0
            return
        }
        target = text
        let remaining = target.dropFirst(displayed.count).count
        if remaining > 0 {
            // Five 50 ms frames catch up with a burst in about 250 ms while
            // keeping the UI below 20 layout updates per second.
            charactersPerTick = max(charactersPerTick, (remaining + 4) / 5)
        }
    }

    @discardableResult mutating func advance() -> Bool {
        guard displayed != target else { charactersPerTick = 0; return false }
        guard target.hasPrefix(displayed) else {
            displayed = target
            charactersPerTick = 0
            return false
        }
        let remaining = target.dropFirst(displayed.count)
        let count = min(remaining.count, max(1, charactersPerTick))
        displayed += String(remaining.prefix(count))
        if displayed == target { charactersPerTick = 0 }
        return displayed != target
    }

    mutating func flush() {
        displayed = target
        charactersPerTick = 0
    }
}

enum AIContractError: Error { case sequenceGap, malformedEvent }

struct AIEvent: Codable, Identifiable, Hashable {
    let seq: Int
    let type: String
    let data: [String: AIJSON]
    let createdAt: String
    var id: Int { seq }
    func requiredText(_ key: String) throws -> String {
        guard case .string(let text) = data[key] else { throw AIContractError.malformedEvent }
        return text
    }
    func text(_ key: String) -> String {
        guard case .string(let text) = data[key] else { return "" }
        return text
    }
}

indirect enum AIJSON: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: AIJSON]), array([AIJSON]), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: AIJSON].self) { self = .object(value) }
        else { self = .array(try container.decode([AIJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    var formatted: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(self), let text = String(data: bytes, encoding: .utf8) else { return "表示できません" }
        return text
    }
}

struct AIEventPage: Decodable { let run: AIRun; let events: [AIEvent] }

struct AITool: Identifiable {
    let id: String
    var name: String
    var arguments: String
    var output: String
    var completed: Bool

    var displayArguments: String {
        if name == "execute_code", let data = arguments.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = object["code"] as? String { return code }
        return Self.readable(arguments, depth: 0)
    }
    var displayOutput: String { Self.readable(output, depth: 0) }

    private static func readable(_ text: String, depth: Int) -> String {
        guard depth < 5, let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return text }
        // Responses tool results may wrap JSON in input_text content blocks.
        // Preserve the stored payload and normalize only its presentation.
        if let blocks = value as? [[String: Any]], !blocks.isEmpty,
           blocks.allSatisfy({ ["input_text", "output_text", "text"].contains($0["type"] as? String ?? "") && $0["text"] is String }) {
            return blocks.compactMap { $0["text"] as? String }.map { readable($0, depth: depth + 1) }.joined(separator: "\n")
        }
        if let nested = value as? String { return readable(nested, depth: depth + 1) }
        guard JSONSerialization.isValidJSONObject(value),
              let formatted = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let result = String(data: formatted, encoding: .utf8) else { return text }
        return result
    }
}

enum AITraceEntry: Identifiable {
    case reasoning(firstSeq: Int, text: String)
    case message(firstSeq: Int, text: String)
    case tool(firstSeq: Int, value: AITool)

    var id: String {
        switch self {
        case .reasoning(let seq, _): return "reasoning.\(seq)"
        case .message(let seq, _): return "message.\(seq)"
        case .tool(_, let tool): return "tool.\(tool.id)"
        }
    }
}

enum AITraceTimelineSection: Identifiable {
    case activities(firstSeq: Int, entries: [AITraceEntry])
    case message(firstSeq: Int, text: String)

    var id: String {
        switch self {
        case .activities(let seq, _): return "activities.\(seq)"
        case .message(let seq, _): return "message.\(seq)"
        }
    }
}

struct AITrace {
    let events: [AIEvent]
    var reasoning: String { events.filter { $0.type == "reasoning.delta" }.map { $0.text("text") }.joined() }
    var status: String {
        guard let event = events.last(where: { $0.type == "status" }), event.data["done"] == .bool(false) else { return "" }
        return event.text("description")
    }
    var tools: [AITool] {
        var result: [AITool] = []
        for event in events where event.type == "tool.call" || event.type == "tool.result" {
            let id = event.text("id")
            if let index = result.firstIndex(where: { $0.id == id }) {
                if event.type == "tool.call" {
                    result[index].name = event.text("name")
                    result[index].arguments = event.text("arguments")
                } else {
                    result[index].output = event.text("output")
                    result[index].completed = true
                }
            } else {
                result.append(AITool(id: id, name: event.text("name"), arguments: event.text("arguments"), output: event.text("output"), completed: event.type == "tool.result"))
            }
        }
        return result
    }

    func timeline(displayedOutput: String) -> [AITraceEntry] {
        var entries: [AITraceEntry] = []
        var messageIndex: Int?
        var reasoningIndex: Int?
        var toolIndexes: [String: Int] = [:]

        for event in events {
            switch event.type {
            case "text.delta":
                let delta = event.text("text")
                if let index = messageIndex,
                   case .message(let firstSeq, let text) = entries[index] {
                    entries[index] = .message(firstSeq: firstSeq, text: text + delta)
                } else if !delta.isEmpty {
                    entries.append(.message(firstSeq: event.seq, text: delta))
                    messageIndex = entries.count - 1
                }
                reasoningIndex = nil
            case "reasoning.delta":
                let delta = event.text("text")
                if let index = reasoningIndex,
                   case .reasoning(let firstSeq, let text) = entries[index] {
                    entries[index] = .reasoning(firstSeq: firstSeq, text: text + delta)
                } else if !delta.isEmpty {
                    entries.append(.reasoning(firstSeq: event.seq, text: delta))
                    reasoningIndex = entries.count - 1
                }
                messageIndex = nil
            case "tool.call", "tool.result":
                messageIndex = nil
                reasoningIndex = nil
                let id = event.text("id")
                if let index = toolIndexes[id],
                   case .tool(let firstSeq, var tool) = entries[index] {
                    if event.type == "tool.call" {
                        tool.name = event.text("name")
                        tool.arguments = event.text("arguments")
                    } else {
                        tool.output = event.text("output")
                        tool.completed = true
                    }
                    entries[index] = .tool(firstSeq: firstSeq, value: tool)
                } else {
                    let tool = AITool(id: id, name: event.text("name"), arguments: event.text("arguments"),
                        output: event.text("output"), completed: event.type == "tool.result")
                    entries.append(.tool(firstSeq: event.seq, value: tool))
                    toolIndexes[id] = entries.count - 1
                }
            default: break
            }
        }

        // The presentation text is a paced prefix of AIRun.outputText. Split
        // that exact prefix across the event-derived message boundaries so a
        // fast stream stays smooth without losing tool/message chronology.
        var remaining = displayedOutput[...]
        var visible: [AITraceEntry] = []
        for entry in entries {
            switch entry {
            case .message(let firstSeq, let rawText):
                let text = remaining.prefix(rawText.count)
                remaining = remaining.dropFirst(text.count)
                if !text.isEmpty { visible.append(.message(firstSeq: firstSeq, text: String(text))) }
            default: visible.append(entry)
            }
        }
        if !remaining.isEmpty {
            visible.append(.message(firstSeq: 0, text: String(remaining)))
        }
        return visible
    }

    func groupedTimeline(displayedOutput: String) -> [AITraceTimelineSection] {
        var sections: [AITraceTimelineSection] = []
        for entry in timeline(displayedOutput: displayedOutput) {
            switch entry {
            case .message(let firstSeq, let text):
                sections.append(.message(firstSeq: firstSeq, text: text))
            case .reasoning(let firstSeq, _), .tool(let firstSeq, _):
                if case .activities(let groupSeq, var entries) = sections.last {
                    entries.append(entry)
                    sections[sections.count - 1] = .activities(firstSeq: groupSeq, entries: entries)
                } else {
                    sections.append(.activities(firstSeq: firstSeq, entries: [entry]))
                }
            }
        }
        return sections
    }
}
