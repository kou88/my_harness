import Foundation

public indirect enum AICronJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: AICronJSON]), array([AICronJSON]), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([String: AICronJSON].self) { self = .object(item) }
        else { self = .array(try value.decode([AICronJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
}

public enum AICronToolset: String, Codable, CaseIterable, Sendable {
    case web
    case browser

    public var name: String {
        switch self {
        case .web: "Web検索"
        case .browser: "ブラウザ操作"
        }
    }
}

public struct AICronRun: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let status: String
    public let preview: String
    public let startedAt: Double
    public let endedAt: Double
}

public struct AICronJob: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let prompt: String
    public let schedule: String
    public let scheduleDisplay: String
    public let scheduleKind: String
    public let enabled: Bool
    public let state: String
    public let nextRunAt: String
    public let lastRunAt: String
    public let lastStatus: String
    public let lastError: String
    public let createdAt: String
    public let model: String
    public let reasoningEffort: String
    public let enabledToolsets: [String]
    public let runs: [AICronRun]
}

public struct AICronSuggestion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let source: String
    public let schedule: String
    public let prompt: String
    public let enabledToolsets: [String]
    public let createdAt: String
}

public struct AICronHostSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { hostId }
    public let hostId: String
    public let hostName: String
    public let online: Bool
    public let revision: Int
    public let capturedAt: String
    public let jobs: [AICronJob]
    public let suggestions: [AICronSuggestion]
}

public struct AICronJobSpec: Codable, Equatable, Sendable {
    public let name: String
    public let prompt: String
    public let schedule: String
    public let model: String
    public let reasoningEffort: String
    public let enabledToolsets: [AICronToolset]

    public init(name: String, prompt: String, schedule: String, model: String,
                reasoningEffort: String, enabledToolsets: [AICronToolset]) {
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.enabledToolsets = enabledToolsets
    }
}

public enum AICronOperationRequest: Equatable, Sendable {
    case create(AICronJobSpec)
    case update(jobId: String, spec: AICronJobSpec)
    case pause(jobId: String)
    case resume(jobId: String)
    case trigger(jobId: String)
    case delete(jobId: String)
    case acceptSuggestion(suggestionId: String)
    case dismissSuggestion(suggestionId: String)
}

extension AICronOperationRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, jobId, suggestionId, name, prompt, schedule, model, reasoningEffort, enabledToolsets
    }
    private enum Kind: String, Codable {
        case create, update, pause, resume, trigger, delete
        case acceptSuggestion = "accept_suggestion"
        case dismissSuggestion = "dismiss_suggestion"
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try value.decode(Kind.self, forKey: .kind)
        func spec() throws -> AICronJobSpec {
            try AICronJobSpec(
                name: value.decode(String.self, forKey: .name),
                prompt: value.decode(String.self, forKey: .prompt),
                schedule: value.decode(String.self, forKey: .schedule),
                model: value.decode(String.self, forKey: .model),
                reasoningEffort: value.decode(String.self, forKey: .reasoningEffort),
                enabledToolsets: value.decode([AICronToolset].self, forKey: .enabledToolsets)
            )
        }
        switch kind {
        case .create: self = .create(try spec())
        case .update: self = .update(jobId: try value.decode(String.self, forKey: .jobId), spec: try spec())
        case .pause: self = .pause(jobId: try value.decode(String.self, forKey: .jobId))
        case .resume: self = .resume(jobId: try value.decode(String.self, forKey: .jobId))
        case .trigger: self = .trigger(jobId: try value.decode(String.self, forKey: .jobId))
        case .delete: self = .delete(jobId: try value.decode(String.self, forKey: .jobId))
        case .acceptSuggestion: self = .acceptSuggestion(suggestionId: try value.decode(String.self, forKey: .suggestionId))
        case .dismissSuggestion: self = .dismissSuggestion(suggestionId: try value.decode(String.self, forKey: .suggestionId))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        func encodeKind(_ kind: Kind) throws { try value.encode(kind, forKey: .kind) }
        func encodeSpec(_ spec: AICronJobSpec) throws {
            try value.encode(spec.name, forKey: .name)
            try value.encode(spec.prompt, forKey: .prompt)
            try value.encode(spec.schedule, forKey: .schedule)
            try value.encode(spec.model, forKey: .model)
            try value.encode(spec.reasoningEffort, forKey: .reasoningEffort)
            try value.encode(spec.enabledToolsets, forKey: .enabledToolsets)
        }
        switch self {
        case .create(let spec): try encodeKind(.create); try encodeSpec(spec)
        case .update(let id, let spec): try encodeKind(.update); try value.encode(id, forKey: .jobId); try encodeSpec(spec)
        case .pause(let id): try encodeKind(.pause); try value.encode(id, forKey: .jobId)
        case .resume(let id): try encodeKind(.resume); try value.encode(id, forKey: .jobId)
        case .trigger(let id): try encodeKind(.trigger); try value.encode(id, forKey: .jobId)
        case .delete(let id): try encodeKind(.delete); try value.encode(id, forKey: .jobId)
        case .acceptSuggestion(let id): try encodeKind(.acceptSuggestion); try value.encode(id, forKey: .suggestionId)
        case .dismissSuggestion(let id): try encodeKind(.dismissSuggestion); try value.encode(id, forKey: .suggestionId)
        }
    }
}

public struct AICronOperation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let hostId: String
    public let kind: String
    public let request: AICronOperationRequest
    public let status: String
    public let result: [String: AICronJSON]
    public let error: String
    public let createdAt: String
    public let updatedAt: String

    public var isTerminal: Bool { status == "succeeded" || status == "failed" }
}

public struct AICronOperationSubmission: Codable, Equatable, Sendable {
    public let id: String
    public let hostId: String
    public let operation: AICronOperationRequest

    public init(id: String, hostId: String, operation: AICronOperationRequest) {
        self.id = id
        self.hostId = hostId
        self.operation = operation
    }
}
