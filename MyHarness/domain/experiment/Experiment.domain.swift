import Foundation

enum ExperimentStatus: String, Decodable, Hashable {
    case active, paused, closed, unverified, testing, supported, refuted, inconclusive
    case pending, inProgress = "in_progress", completed, canceled

    var title: String {
        switch self {
        case .active, .inProgress: "進行中"
        case .paused: "保留"
        case .closed: "終了"
        case .unverified: "未検証"
        case .testing: "検証中"
        case .supported: "支持"
        case .refuted: "否定"
        case .inconclusive: "判断保留"
        case .pending: "未着手"
        case .completed: "完了"
        case .canceled: "中止"
        }
    }
}

struct ExperimentThemeSummary: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let status: ExperimentStatus
    let hypothesisCount: Int
    let testingHypothesisCount: Int
    let openTaskCount: Int
    let lastActivityAt: Date
}

struct ExperimentTheme: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let audience: String
    let constraints: String
    let status: ExperimentStatus
    let updatedAt: Date
    let archivedAt: Date?
}

struct ExperimentHypothesis: Decodable, Identifiable, Hashable {
    let id: String
    let themeId: String
    let definitionRevisionId: String
    let statement: String
    let background: String
    let question: String
    let successCriteria: String
    let falsificationCriteria: String
    let status: ExperimentStatus
    let updatedAt: Date
    let archivedAt: Date?
}

struct ExperimentTask: Decodable, Identifiable, Hashable {
    let id: String
    let hypothesisId: String
    let hypothesisRevisionId: String
    let title: String
    let method: String
    let expectedOutcome: String
    let status: ExperimentStatus
    let dueAt: Date?
    let completionReason: String
    let completedAt: Date?
    let archivedAt: Date?
    var isFinished: Bool { status == .completed || status == .canceled }
}

struct ExperimentNote: Decodable, Identifiable, Hashable {
    struct Source: Decodable, Hashable {
        let label: String
        let url: URL
    }
    let id: String
    let taskId: String
    let revisionId: String
    let version: Int
    let title: String
    let observedAt: Date
    let facts: String
    let interpretation: String
    let sources: [Source]
    let findings: String
    let unresolved: String
    let nextCandidates: String
    let createdAt: Date
    let updatedAt: Date
    let updatedBy: String
    let archivedAt: Date?
}

struct ExperimentJudgment: Decodable, Identifiable, Hashable {
    let id: String
    let hypothesisId: String
    let hypothesisRevisionId: String
    let decision: ExperimentStatus
    let reason: String
    let actor: String
    let createdAt: Date
}

struct ExperimentJudgmentDetail: Decodable, Identifiable, Hashable {
    let id: String
    let hypothesisRevisionId: String
    let decision: ExperimentStatus
    let reason: String
    let createdAt: Date
    let evidenceRevisionIds: [String]
}

struct ExperimentTree: Decodable, Hashable {
    let theme: ExperimentTheme
    let hypotheses: [ExperimentHypothesis]
    let tasks: [ExperimentTask]
    let notes: [ExperimentNote]
    let judgments: [ExperimentJudgment]

    var visibleHypotheses: [ExperimentHypothesis] {
        hypotheses.filter { $0.archivedAt == nil }
    }
    var visibleTasks: [ExperimentTask] {
        let hypothesisIDs = Set(visibleHypotheses.map(\.id))
        return tasks.filter { $0.archivedAt == nil && hypothesisIDs.contains($0.hypothesisId) }
    }
    var visibleNotes: [ExperimentNote] {
        let taskIDs = Set(visibleTasks.map(\.id))
        return notes.filter { $0.archivedAt == nil && taskIDs.contains($0.taskId) }
            .sorted { $0.observedAt > $1.observedAt }
    }

    func tasks(for hypothesis: ExperimentHypothesis) -> [ExperimentTask] {
        tasks.filter { $0.hypothesisId == hypothesis.id && $0.archivedAt == nil }
    }
    func notes(for task: ExperimentTask) -> [ExperimentNote] {
        notes.filter { $0.taskId == task.id && $0.archivedAt == nil }
            .sorted { $0.observedAt > $1.observedAt }
    }
}

struct ExperimentPage<Item: Decodable>: Decodable {
    let items: [Item]
    let total: Int
    let limit: Int
    let offset: Int
    var hasMore: Bool { offset + items.count < total }
}
struct ExperimentEnvelope<Item: Decodable>: Decodable { let data: Item }
struct ExperimentRevision<Item: Decodable>: Decodable, Identifiable {
    let id: String
    let version: Int
    let snapshot: Item
    let reason: String
    let actor: String
    let createdAt: Date
}
