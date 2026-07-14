import SwiftUI

struct ProductOpsAccessPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct ProductOpsMessageBar: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
    }
}

struct ProductOpsTokenView: View {
    let text: String
    let systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

enum ProductOpsDisplay {
    static let statusOptions = [
        "backlog",
        "ready",
        "in_progress",
        "review",
        "done",
        "canceled"
    ]

    static let priorityOptions = [
        "high",
        "medium",
        "low"
    ]

    static let executorOptions = [
        "codex",
        "manual"
    ]

    static func statusLabel(_ value: String) -> String {
        switch value {
        case "backlog":
            return "バックログ"
        case "ready":
            return "着手可"
        case "in_progress":
            return "進行中"
        case "review":
            return "確認待ち"
        case "done":
            return "完了"
        case "canceled":
            return "取消"
        default:
            return value
        }
    }

    static func priorityLabel(_ value: String) -> String {
        switch value {
        case "high":
            return "高"
        case "medium":
            return "中"
        case "low":
            return "低"
        default:
            return value
        }
    }

    static func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
