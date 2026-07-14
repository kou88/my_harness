import SwiftUI

@MainActor
struct ActionInboxView: View {
    @Environment(AppRouter.self) private var router
    let state: ActionInboxState

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle("おすすめ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if state.isSignedIn {
                        Button {
                            Task { await state.registerForPushNotifications() }
                        } label: {
                            Label("通知を有効化", systemImage: "bell.badge")
                        }
                        .disabled(state.isRegisteringPush)

                        Button(role: .destructive) {
                            Task { await state.signOut() }
                        } label: {
                            Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            Task { await state.signIn() }
                        } label: {
                            Label("ログイン", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .disabled(!state.isConfigured || state.isSigningIn)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("おすすめ操作")
            }
        }
        .refreshable {
            await state.loadIfPossible()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = state.message {
                ActionMessageBar(text: message, systemImage: "info.circle")
            }
        }
        .task {
            await state.loadIfPossible()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let configurationErrorMessage = state.configurationErrorMessage {
            ActionInboxPlaceholder(
                title: "API設定が未完了",
                systemImage: "gearshape.2",
                message: configurationErrorMessage,
                footnote: "ActionAPIBaseURL / CognitoHostedUIBaseURL / CognitoClientID を設定してください。"
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        } else if !state.isSignedIn {
            ActionInboxPlaceholder(
                title: "ログインが必要です",
                systemImage: "person.crop.circle",
                message: "Cognito Hosted UIでログインします。"
            ) {
                ActionInboxLoginButton(
                    isSigningIn: state.isSigningIn,
                    action: {
                        Task { await state.signIn() }
                    }
                )
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        } else {
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
                    Label("読み込みに失敗しました", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .listRowSeparator(.hidden)
            case .loaded(let payload):
                if payload.items.isEmpty {
                    ActionInboxPlaceholder(
                        title: "おすすめはありません",
                        systemImage: "sparkles"
                    )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                } else {
                    ActionInboxSummaryRow(
                        pendingCount: state.pendingCount,
                        highRiskCount: state.highRiskCount,
                        updatedAt: payload.summary?.updatedAt
                    )
                    .listRowSeparator(.hidden)

                    ForEach(payload.items) { item in
                        Button {
                            router.push(.actionSuggestionDetail(id: item.id))
                        } label: {
                            ActionInboxItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ActionInboxPlaceholder<Action: View>: View {
    let title: String
    let systemImage: String
    let message: String?
    let footnote: String?
    @ViewBuilder let action: () -> Action

    init(
        title: String,
        systemImage: String,
        message: String? = nil,
        footnote: String? = nil,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.footnote = footnote
        self.action = action
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }

            action()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}

extension ActionInboxPlaceholder where Action == EmptyView {
    init(
        title: String,
        systemImage: String,
        message: String? = nil,
        footnote: String? = nil
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            message: message,
            footnote: footnote
        ) {
            EmptyView()
        }
    }
}

private struct ActionInboxLoginButton: View {
    let isSigningIn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }

                Text(isSigningIn ? "ログイン中" : "ログイン")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 176, height: 52)
            .background(Color.accentColor, in: Capsule())
            .opacity(isSigningIn ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
        .accessibilityLabel(isSigningIn ? "ログイン中" : "ログイン")
    }
}

private struct ActionMessageBar: View {
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

private struct ActionInboxSummaryRow: View {
    let pendingCount: Int
    let highRiskCount: Int
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Label("\(pendingCount)", systemImage: "tray.full")
                .monospacedDigit()
            if highRiskCount > 0 {
                Label("\(highRiskCount)", systemImage: "exclamationmark.triangle")
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            if let updatedAt {
                Text(ActionDateFormat.string(from: updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.vertical, 4)
    }
}

private struct ActionInboxItemRow: View {
    let item: ActionInboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.displayRiskLevel.tint)
                .frame(width: 9, height: 9)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let version = item.version ?? item.expectedVersion {
                        Text("v\(version)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(item.displayRiskLevel.label)
                        .foregroundStyle(item.displayRiskLevel.tint)
                    if let actionType = item.actionType {
                        Text(actionType)
                    }
                    if let dueAt = item.dueAt {
                        Text(ActionDateFormat.string(from: dueAt))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

@MainActor
struct ActionSuggestionDetailView: View {
    enum ConfirmingAction: String, Identifiable {
        case approve
        case adoptResult
        case rejectResult
        case cancel

        var id: String { rawValue }

        var title: String {
            switch self {
            case .approve:
                return "このおすすめを承認しますか？"
            case .adoptResult:
                return "結果を採用しますか？"
            case .rejectResult:
                return "結果を却下しますか？"
            case .cancel:
                return "このおすすめをキャンセルしますか？"
            }
        }
    }

    @Environment(AppRouter.self) private var router
    let id: String
    let state: ActionInboxState
    @State private var decisionNote = ""
    @State private var confirmingAction: ConfirmingAction?

    var body: some View {
        List {
            switch state.detailState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            case .failed(let message):
                ContentUnavailableView {
                    Label("詳細を読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .listRowSeparator(.hidden)
            case .loaded(let suggestion):
                detailContent(suggestion)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("おすすめ詳細")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await state.loadSuggestion(id: id)
        }
        .task(id: id) {
            await state.loadSuggestion(id: id)
        }
        .safeAreaInset(edge: .bottom) {
            if let suggestion = state.currentSuggestion {
                actionBar(suggestion)
            }
        }
        .alert(
            confirmingAction?.title ?? "",
            isPresented: Binding(
                get: { confirmingAction != nil },
                set: { if !$0 { confirmingAction = nil } }
            )
        ) {
            Button("実行", role: confirmingAction == .cancel || confirmingAction == .rejectResult ? .destructive : nil) {
                guard let action = confirmingAction, let suggestion = state.currentSuggestion else { return }
                confirmingAction = nil
                Task { await perform(action, suggestion: suggestion) }
            }
            Button("戻る", role: .cancel) {
                confirmingAction = nil
            }
        } message: {
            Text("version \(state.currentSuggestion?.version ?? 0) を使って送信します。古い通知や古い画面からの誤操作はAPI側で拒否されます。")
        }
    }

    @ViewBuilder
    private func detailContent(_ suggestion: ActionSuggestion) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(suggestion.displayTitle)
                    .font(.headline)
                Text(suggestion.detailText)
                    .font(.body)
                    .textSelection(.enabled)
                metadataRows(suggestion)
            }
            .padding(.vertical, 4)
        }

        if !suggestion.researchResults.isEmpty {
            Section("調査結果") {
                ForEach(suggestion.researchResults) { result in
                    ActionResearchResultView(result: result)
                }
            }
        }

        if !suggestion.needEvidence.isEmpty {
            Section("Evidence") {
                ForEach(suggestion.needEvidence) { evidence in
                    ActionEvidenceItemView(evidence: evidence)
                }
            }
        }

        if !suggestion.sourceItems.isEmpty {
            Section("Source Items") {
                ForEach(suggestion.sourceItems) { evidence in
                    ActionEvidenceItemView(evidence: evidence)
                }
            }
        }

        Section("操作メモ") {
            TextEditor(text: $decisionNote)
                .frame(minHeight: 90)
                .overlay(alignment: .topLeading) {
                    if decisionNote.isEmpty {
                        Text("必要なら判断メモ")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                }
        }

        Section("関連") {
            if let executionId = suggestion.executionId {
                referenceButton(title: "実行", systemImage: "terminal", route: .actionExecution(id: executionId))
            }
            if let needId = suggestion.needId {
                referenceButton(title: "ニーズ", systemImage: "lightbulb", route: .need(id: needId))
            }
            if let codexResultId = suggestion.codexResultId {
                referenceButton(title: "Codex結果", systemImage: "doc.text.magnifyingglass", route: .codexResult(id: codexResultId))
            }
            if let sourceURL = suggestion.sourceURL {
                Link(destination: sourceURL) {
                    Label("ソースURL", systemImage: "link")
                }
            }
        }
    }

    private func metadataRows(_ suggestion: ActionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("リスク \(suggestion.displayRiskLevel.label)")
                    .foregroundStyle(suggestion.displayRiskLevel.tint)
                Text("v\(suggestion.version)")
                    .monospacedDigit()
                if let status = suggestion.status {
                    Text(status)
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)

            HStack(spacing: 8) {
                if let actionType = suggestion.actionType {
                    Text(actionType)
                }
                if let sourceType = suggestion.sourceType {
                    Text(sourceType)
                }
                if let updatedAt = suggestion.updatedAt ?? suggestion.createdAt {
                    Text(ActionDateFormat.string(from: updatedAt))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func referenceButton(title: String, systemImage: String, route: AppRoute) -> some View {
        Button {
            router.push(route)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func actionBar(_ suggestion: ActionSuggestion) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    Task { await state.decide(suggestion: suggestion, decision: .rejected, decisionNote: decisionNote) }
                } label: {
                    Label("却下", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await state.decide(suggestion: suggestion, decision: .later, decisionNote: decisionNote) }
                } label: {
                    Label("後で", systemImage: "clock")
                }
                .buttonStyle(.bordered)

                Button {
                    if suggestion.shouldConfirmApprovalInApp {
                        confirmingAction = .approve
                    } else {
                        Task { await state.decide(suggestion: suggestion, decision: .approved, decisionNote: decisionNote) }
                    }
                } label: {
                    Label("承認", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                Button {
                    confirmingAction = .adoptResult
                } label: {
                    Label("結果採用", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    confirmingAction = .rejectResult
                } label: {
                    Label("結果却下", systemImage: "hand.thumbsdown")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    confirmingAction = .cancel
                } label: {
                    Label("キャンセル", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .disabled(state.isPostingDecision)
    }

    private func perform(_ action: ConfirmingAction, suggestion: ActionSuggestion) async {
        switch action {
        case .approve:
            await state.decide(suggestion: suggestion, decision: .approved, decisionNote: decisionNote)
        case .adoptResult:
            await state.adoptResult(suggestion: suggestion, decisionNote: decisionNote)
        case .rejectResult:
            await state.rejectResult(suggestion: suggestion, decisionNote: decisionNote)
        case .cancel:
            await state.cancel(suggestion: suggestion, decisionNote: decisionNote)
        }
    }
}

private struct ActionResearchResultView: View {
    let result: ActionSuggestionResearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.displayTitle)
                .font(.subheadline.weight(.semibold))
            Text(result.displayBody)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !result.needEvidence.isEmpty || !result.sourceItems.isEmpty {
                Text("Evidence \(result.needEvidence.count) / Source \(result.sourceItems.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ActionEvidenceItemView: View {
    let evidence: ActionSuggestionEvidenceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(evidence.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let sourceType = evidence.sourceType {
                    Text(sourceType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(evidence.displayBody)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let author = evidence.author {
                    Text(author)
                }
                if let capturedAt = evidence.capturedAt {
                    Text(ActionDateFormat.string(from: capturedAt))
                }
                if let sourceURL = evidence.sourceURL {
                    Link("開く", destination: sourceURL)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

enum ActionReferenceKind {
    case execution
    case need
    case codexResult

    var title: String {
        switch self {
        case .execution:
            return "実行"
        case .need:
            return "ニーズ"
        case .codexResult:
            return "Codex結果"
        }
    }

    var systemImage: String {
        switch self {
        case .execution:
            return "terminal"
        case .need:
            return "lightbulb"
        case .codexResult:
            return "doc.text.magnifyingglass"
        }
    }
}

struct ActionReferenceView: View {
    let kind: ActionReferenceKind
    let id: String

    var body: some View {
        ContentUnavailableView {
            Label(kind.title, systemImage: kind.systemImage)
        } description: {
            Text(id)
                .font(.body.monospaced())
                .textSelection(.enabled)
        } actions: {
            Text("詳細APIが接続されたらここに読み取り画面を追加します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum ActionDateFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
