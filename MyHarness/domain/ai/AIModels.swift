import Foundation

struct AISharing: Codable, Equatable {
    var enabled: Bool
    var modelId: String
    var contextLength: Int
    var revision: Int
}

struct AISettings: Codable, Hashable {
    var contextLength: Int
    var maxOutputTokens: Int
    var reasoningEffort: String
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

    func accepts(_ settings: AISettings) -> Bool {
        guard let budget = reasoningBudgets[settings.reasoningEffort] else { return false }
        return contextLengths.contains(settings.contextLength)
            && reasoningEfforts.contains(settings.reasoningEffort)
            && settings.maxOutputTokens >= budget + 256
            && settings.maxOutputTokens <= maxOutputTokens
            && settings.maxOutputTokens < settings.contextLength
    }
}

struct AIConversation: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let createdAt: String
    var updatedAt: String
}

struct AIConversationDetail: Codable, Identifiable {
    let id: String
    var title: String
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
    let inputText: String
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
}
