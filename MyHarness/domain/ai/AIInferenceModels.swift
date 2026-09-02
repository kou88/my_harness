import Foundation

struct AIInferenceModelPolicy: Codable, Equatable, Identifiable {
    let model: String
    var chatContextLength: Int
    var apiContextLength: Int
    var scheduledContextLength: Int
    var auxiliaryContextLength: Int
    var id: String { model }
}
struct AIInferencePolicy: Codable, Equatable {
    var revision: Int
    var maxConcurrentInferences: Int
    var models: [AIInferenceModelPolicy]
}
struct AIInferenceCapability: Decodable, Equatable, Identifiable {
    let model: String
    let contextLengths: [Int]
    let totalContextTokens: Int
    let maxConcurrentInferences: Int
    let maxOutputTokens: Int
    let initialOutputTokens: Int
    var id: String { model }
}
struct AIInferenceJob: Decodable, Equatable, Identifiable {
    let id: String
    let source: String
    let model: String
    let contextLength: Int
    let state: String
    let position: Int
    let waitSeconds: Int
    let reason: String
    var sourceName: String {
        switch source { case "chat": "チャット"; case "api": "外部API"; case "scheduled": "定期タスク"; case "auxiliary": "補助推論"; default: source }
    }
    var statusText: String {
        if state == "draining" { return "切断後の生成終了を確認中" }
        switch reason {
        case "model_switch": return "モデル切り替え待ち"
        case "concurrency": return "推論枠待ち"
        case "context_capacity": return "コンテキスト容量待ち"
        case "backend_recovery": return "バックエンド停止確認中"
        case "arrival_order": return "先のリクエストを待機中"
        default: return state == "prefill" ? "入力処理中" : "生成中"
        }
    }
}
struct AIInferenceSnapshot: Decodable, Equatable {
    let policy: AIInferencePolicy
    let capabilities: [AIInferenceCapability]
    let loadedModel: String
    let phase: String
    let error: String
    let reservedContextTokens: Int
    let active: [AIInferenceJob]
    let queued: [AIInferenceJob]
}
struct AIInferenceHost: Decodable, Equatable, Identifiable {
    let hostId: String
    let hostName: String
    let online: Bool
    let capturedAt: String
    var desiredPolicy: AIInferencePolicy
    let state: AIInferenceSnapshot
    var id: String { hostId }
    var isApplied: Bool { desiredPolicy == state.policy }
}
