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

struct AIPowerOperation: Codable, Equatable, Identifiable {
    let id: String
    let hostId: String
    let action: String
    let status: String
    let bootId: String
    let error: String
    let createdAt: String
    let updatedAt: String
    let expiresAt: String
    var isActive: Bool { ["queued", "waking", "draining", "stopping"].contains(status) }
    var canCancel: Bool { action != "wake" && ["queued", "draining"].contains(status) }
    var title: String { action == "wake" ? "起動" : action == "shutdown" ? "シャットダウン" : "作業完了後に停止" }
    var statusText: String {
        switch status {
        case "queued": "受付済み"
        case "waking": "起動信号送信済み・準備待ち"
        case "draining": "作業の完了待ち"
        case "stopping": "停止処理中"
        case "succeeded": "完了"
        case "cancelled": "取消済み"
        case "expired": "期限切れ"
        case "failed": "失敗"
        default: "不明"
        }
    }
}
struct AIPowerHost: Decodable, Equatable, Identifiable {
    let hostId: String
    let hostName: String
    let relayOnline: Bool
    let online: Bool
    let state: String
    let aiReady: Bool
    let capturedAt: String
    let activeRuns: Int
    let queuedRuns: Int
    let blockers: [String]
    let error: String
    let operations: [AIPowerOperation]
    var id: String { hostId }
    var hasActiveOperation: Bool { operations.contains(where: \.isActive) }
    var stateText: String {
        switch state {
        case "starting": "起動中"
        case "online": "稼働中"
        case "waiting": "停止待ち"
        case "stopping": "停止処理中"
        case "stopped": "停止確認済み"
        default: "接続不明"
        }
    }
}

// Power reports and the chat Agent connection are independent observations.
struct AISharingConnection: Equatable {
    let pc: String
    let agent: String
    let ai: String
    let message: String

    init(model: AIModel, power: AIPowerHost?, catalogError: String, powerError: String) {
        agent = catalogError.isEmpty ? (model.online ? "接続中" : "未接続") : "確認できません"
        guard powerError.isEmpty, let power else {
            pc = "状態未取得"
            ai = "状態未取得"
            message = powerError.isEmpty ? "PCの稼働状態はまだ取得できていません。" : "PCの状態を取得できませんでした。"
            return
        }
        pc = power.stateText
        ai = power.online ? (power.aiReady ? "利用可能" : "準備中・要確認") : "状態未取得"
        if power.online && !power.aiReady {
            message = power.error.isEmpty ? "PCは稼働中ですが、AIの準備が完了していません。" : power.error
        } else if power.online && !model.online && catalogError.isEmpty {
            message = "PCは稼働中ですが、OS Agentに接続できません。"
        } else {
            message = ""
        }
    }
}
