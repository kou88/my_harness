import Foundation

enum AIProvider: String, Codable, CaseIterable, Hashable {
    case openai
    case openrouter

    var label: String {
        switch self {
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        }
    }
}

enum AIConversationMode: String, Codable, CaseIterable, Hashable {
    case consultation
    case work

    var label: String {
        switch self {
        case .consultation: return "相談"
        case .work: return "作業"
        }
    }

    var systemImage: String {
        switch self {
        case .consultation: return "bubble.left.and.text.bubble.right"
        case .work: return "hammer"
        }
    }
}

enum AIReasoningEffort: String, Codable, CaseIterable, Hashable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    var label: String {
        switch self {
        case .none: return "なし"
        case .minimal: return "最小"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .xhigh: return "最高"
        case .max: return "最大"
        case .ultra: return "ウルトラ"
        }
    }
}

enum AIConversationStatus: String, Codable, Hashable {
    case idle
    case queued
    case running
    case awaitingApproval = "waiting_approval"
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .idle: return "待機中"
        case .queued: return "実行待ち"
        case .running: return "実行中"
        case .awaitingApproval: return "承認待ち"
        case .completed: return "完了"
        case .failed: return "失敗"
        case .cancelled: return "停止"
        }
    }

    var isActive: Bool {
        self == .queued || self == .running || self == .awaitingApproval
    }
}

enum AIConversationLifecycleStatus: String, Codable, Hashable {
    case active
    case archived
}

enum AIMessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

enum AIMessageStatus: String, Codable, Hashable {
    case pending
    case streaming
    case completed
    case failed
}

enum AIContentType: String, Codable, Hashable {
    case text
    case markdown
    case image
    case file
}

struct AIModelCatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let model: String
    let runtimeId: String
    let hostId: String
    let hostName: String
    let provider: AIProvider
    let name: String
    let displayName: String
    let status: String
    let isAvailable: Bool
    let reasoningEfforts: [AIReasoningEffort]
    let supportsImages: Bool
    let supportsFiles: Bool
    let supportsTools: Bool
}

struct AIRuntimeSummary: Codable, Identifiable, Hashable {
    let id: String
    let runtimeId: String
    let provider: AIProvider
    let authKind: String
    let status: String
    let authenticated: Bool
    let modelIds: [String]
}

struct AIHostSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let hostname: String?
    let os: String?
    let status: String
    let online: Bool
    let lastSeenAt: Date?
    let runtimes: [AIRuntimeSummary]

    var isOnline: Bool { online }
}

struct AIWorkspaceSummary: Codable, Identifiable, Hashable {
    let id: String
    let workspaceId: String
    let hostId: String
    let hostName: String
    let runtimeId: String
    let name: String
    let path: String
    let modes: [AIConversationMode]
    let status: String
    let isAvailable: Bool
}

struct AIConversationSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let runtimeId: String
    let provider: AIProvider
    let model: String
    let hostId: String
    let workspaceId: String
    let mode: AIConversationMode
    let status: AIConversationLifecycleStatus
    let latestRunStatus: AIConversationStatus
    let reasoningEffort: AIReasoningEffort
    let workspacePath: String
    let lastMessagePreview: String
    let createdAt: Date
    let updatedAt: Date
}

struct AIMessageContent: Codable, Identifiable, Hashable {
    let id: String
    let contentType: AIContentType
    let text: String?
    let attachmentId: String?
    let ordinal: Int
}

struct AIMessage: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let runtimeSessionId: String
    let runId: String
    let role: AIMessageRole
    let status: AIMessageStatus
    let parentMessageId: String?
    let contents: [AIMessageContent]
    let createdAt: Date
    let updatedAt: Date

    var text: String {
        contents
            .filter { $0.contentType == .text || $0.contentType == .markdown }
            .sorted { $0.ordinal < $1.ordinal }
            .compactMap(\.text)
            .joined(separator: "\n")
    }
}

enum AIRunStatus: String, Codable, Hashable {
    case queued
    case running
    case awaitingApproval = "waiting_approval"
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

struct AIRun: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let runtimeSessionId: String
    let userMessageId: String
    let assistantMessageId: String?
    let hostId: String
    let runtimeId: String
    let provider: AIProvider
    let model: String
    let workspaceId: String
    let workspacePath: String
    let mode: AIConversationMode
    let sandboxPolicy: String
    let approvalPolicy: String
    let reasoningEffort: AIReasoningEffort
    let status: AIRunStatus
    let lastSeq: Int
    let inputTokens: Int
    let outputTokens: Int
    let errorCode: String?
    let errorMessage: String?
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let updatedAt: Date
}

enum AIEventType: String, Codable, Hashable {
    case runStarted = "run.started"
    case runStatusChanged = "run.status_changed"
    case messageStarted = "message.started"
    case messageDelta = "message.delta"
    case messageCompleted = "message.completed"
    case reasoningStarted = "reasoning.started"
    case reasoningDelta = "reasoning.delta"
    case reasoningCompleted = "reasoning.completed"
    case toolCallStarted = "tool_call.started"
    case toolCallUpdated = "tool_call.updated"
    case toolCallCompleted = "tool_call.completed"
    case fileChangeCreated = "file_change.created"
    case commandStarted = "command.started"
    case commandOutput = "command.output"
    case commandCompleted = "command.completed"
    case approvalRequired = "approval.required"
    case approvalResolved = "approval.resolved"
    case usageUpdated = "usage.updated"
    case runCompleted = "run.completed"
    case runFailed = "run.failed"
    case runCancelled = "run.cancelled"
}

struct AIEvent: Codable, Identifiable, Hashable {
    let id: String
    let seq: Int
    let runId: String
    let conversationId: String
    let type: AIEventType
    let payload: [String: AIJSONValue]
    let createdAt: Date

    var displayText: String {
        payload["text"]?.stringValue
            ?? payload["delta"]?.stringValue
            ?? payload["summary"]?.stringValue
            ?? payload["command"]?.stringValue
            ?? payload["path"]?.stringValue
            ?? ""
    }
}

enum AIJSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AIJSONValue])
    case array([AIJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AIJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([AIJSONValue].self))
        }
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

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

struct AIApproval: Codable, Identifiable, Hashable {
    let id: String
    let runId: String
    let conversationId: String
    let toolCallId: String?
    let kind: String
    let title: String
    let detail: String
    let riskLevel: String
    let status: String
    let allowForSession: Bool
    let decision: String?
    let requestedAt: Date
    let resolvedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct AIConversationDetail: Codable, Hashable {
    let conversation: AIConversationSummary
    let messages: [AIMessage]
    let run: AIRun?
    let events: [AIEvent]
    let approvals: [AIApproval]
}

struct AITurnAccepted: Codable, Hashable {
    let runId: String
    let conversationId: String
    let status: AIRunStatus
}

struct AIAttachment: Codable, Identifiable, Hashable {
    let id: String
    let conversationId: String
    let fileName: String
    let contentType: String
    let byteSize: Int
    let createdAt: Date
}

struct AINewConversationDraft: Hashable {
    let title: String
    let runtimeId: String
    let hostId: String
    let provider: AIProvider
    let model: String
    let mode: AIConversationMode
    let workspaceId: String
    let reasoningEffort: AIReasoningEffort
    let isTemporary: Bool
}
