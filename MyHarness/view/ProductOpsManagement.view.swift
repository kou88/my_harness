import SwiftUI

@MainActor
struct ProductNeedListView: View {
    let state: ProductOpsState

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 46)
        .navigationTitle("ニーズ一覧")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await state.loadNeedsIfPossible()
        }
        .task {
            await state.loadNeedsIfPossible()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = state.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let configurationErrorMessage = state.configurationErrorMessage {
            ProductOpsAccessPlaceholder(
                title: "API設定が未完了",
                systemImage: "gearshape.2",
                message: configurationErrorMessage
            )
            .listRowSeparator(.hidden)
        } else if !state.isSignedIn {
            ProductOpsAccessPlaceholder(
                title: "ログインが必要です",
                systemImage: "person.crop.circle",
                message: "次にやる画面のメニューからログインしてください。"
            )
            .listRowSeparator(.hidden)
        } else {
            switch state.needsState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            case .failed(let message):
                ContentUnavailableView {
                    Label("ニーズを読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .listRowSeparator(.hidden)
            case .loaded(let needs):
                if needs.isEmpty {
                    Text("ニーズはありません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(needs) { need in
                        NeedListRow(need: need)
                    }
                }
            }
        }
    }
}

private struct NeedListRow: View {
    let need: Need

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(need.displaySummary)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let sourceText = need.sourceText, !sourceText.isEmpty {
                Text(sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if let status = need.status {
                    ProductOpsTokenView(status)
                }
                if let priority = need.priority {
                    ProductOpsTokenView(priority, systemImage: "flag")
                }
                if let sourceType = need.sourceType {
                    ProductOpsTokenView(sourceType, systemImage: "link")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

@MainActor
struct ActionHistoryView: View {
    enum Mode {
        case history
        case completed
    }

    let state: ActionInboxState
    let mode: Mode

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 46)
        .navigationTitle(mode == .completed ? "完了した項目" : "実行履歴")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await state.loadIfPossible()
        }
        .task {
            await state.loadIfPossible()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.inboxState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
        case .failed(let message):
            ContentUnavailableView {
                Label("履歴を読み込めません", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            .listRowSeparator(.hidden)
        case .loaded(let payload):
            let items = filteredItems(payload.items)
            if items.isEmpty {
                Text(mode == .completed ? "完了した項目はありません" : "履歴はありません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HistoryRow(item: item)
                }
            }
        }
    }

    private func filteredItems(_ items: [ActionInboxItem]) -> [ActionInboxItem] {
        switch mode {
        case .history:
            return items
        case .completed:
            return items.filter { $0.status == "completed" }
        }
    }
}

private struct HistoryRow: View {
    let item: ActionInboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.displaySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let status = item.status {
                    ProductOpsTokenView(status)
                }
                if let actionType = item.actionType {
                    ProductOpsTokenView(actionType)
                }
                ProductOpsTokenView(item.displayRiskLevel.label)
            }
        }
        .padding(.vertical, 6)
    }
}
