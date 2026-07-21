import SwiftUI

enum ResearchClipAssociationLoadState: Hashable {
    case loading
    case loaded(VentureResearchClipAssociationOptions)
    case failed(String)
}

struct ResearchClipListView: View {
    let state: ProductOpsState
    let onOpenMission: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var grouping: Grouping = .savedAt
    @State private var associationState: ResearchClipAssociationLoadState = .loading
    @State private var selectedItem: VentureResearchClipListItem?
    @State private var loadMoreError: String?

    private enum Grouping: String, CaseIterable, Identifiable {
        case savedAt
        case opportunity
        case hypothesis
        case mission

        var id: String { rawValue }

        var label: String {
            switch self {
            case .savedAt: return "保存日"
            case .opportunity: return "Opportunity"
            case .hypothesis: return "Hypothesis"
            case .mission: return "元Mission"
            }
        }
    }

    var body: some View {
        Group {
            switch state.researchClipsState {
            case .idle, .loading:
                ProgressView()
                    .accessibilityLabel("保存した調査メモを読み込み中")
            case .failed(let message):
                ContentUnavailableView {
                    Label("調査メモを読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("再試行") { Task { await load() } }
                }
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentUnavailableView(
                        "保存した調査メモはありません",
                        systemImage: "bookmark",
                        description: Text("調査結果の各項目にあるブックマークから保存できます。")
                    )
                } else {
                    clipList(page)
                }
            }
        }
        .navigationTitle("保存した調査メモ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("グループ", selection: $grouping) {
                    ForEach(Grouping.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") { dismiss() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ResearchClipEditView(
                    state: state,
                    clip: item.clip,
                    sourceState: item.sourceState,
                    associationState: associationState,
                    onRetryAssociations: {
                        Task { await loadAssociationOptions() }
                    },
                    onOpenMission: {
                        selectedItem = nil
                        onOpenMission(item.sourceState.sourceMissionId)
                    },
                    onUpdated: { updated in
                        selectedItem = VentureResearchClipListItem(
                            clip: updated,
                            knowledgeStatus: item.knowledgeStatus,
                            sourceState: item.sourceState
                        )
                    },
                    onArchived: {
                        selectedItem = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func clipList(_ page: VentureResearchClipPage) -> some View {
        List {
            if case .failed(let message) = associationState {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("関連候補を再読み込み") {
                            Task { await loadAssociationOptions() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            ForEach(groupedItems(page.items), id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        researchClipRow(item)
                    }
                }
            }

            if page.nextCursor != nil || loadMoreError != nil {
                Section {
                    if let loadMoreError {
                        Text(loadMoreError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("追加読み込みエラー。\(loadMoreError)")
                    }
                    Button {
                        Task { await loadMore() }
                    } label: {
                        if state.isLoadingMoreResearchClips {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .accessibilityHidden(true)
                                Text("読み込み中")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(loadMoreError == nil ? "さらに表示" : "続きを再試行")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(state.isLoadingMoreResearchClips || page.nextCursor == nil)
                    .accessibilityLabel(
                        state.isLoadingMoreResearchClips
                            ? "調査メモの続きを読み込み中"
                            : (loadMoreError == nil ? "調査メモをさらに表示" : "調査メモの続きを再試行")
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func researchClipRow(_ item: VentureResearchClipListItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.clip.textSnapshot)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(item.clip.itemKind.label)
                    Text(item.clip.relation.label)
                    Text(sourceStateLabel(item.sourceState))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !item.clip.userNote.isEmpty {
                    Text(item.clip.userNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(item.clip.itemKind.label)、未採用の調査メモ。\(item.clip.textSnapshot)。\(sourceStateLabel(item.sourceState))"
        )
        .accessibilityHint("ダブルタップでメモ、関連付け、元の情報源を確認します")
    }

    private func groupedItems(_ items: [VentureResearchClipListItem]) -> [(title: String, items: [VentureResearchClipListItem])] {
        let grouped = Dictionary(grouping: items) { item in groupTitle(item) }
        return grouped
            .map { (title: $0.key, items: $0.value.sorted { $0.clip.createdAt > $1.clip.createdAt }) }
            .sorted {
                grouping == .savedAt ? $0.title > $1.title : $0.title < $1.title
            }
    }

    private func groupTitle(_ item: VentureResearchClipListItem) -> String {
        switch grouping {
        case .savedAt:
            return Self.dayFormatter.string(from: item.clip.createdAt)
        case .opportunity:
            guard let id = item.clip.opportunityId else { return "未関連付け" }
            guard case .loaded(let options) = associationState else { return "関連候補を読み込み中" }
            return options.opportunities.first { $0.id == id }?.title ?? id
        case .hypothesis:
            guard let id = item.clip.hypothesisId else { return "未関連付け" }
            guard case .loaded(let options) = associationState else { return "関連候補を読み込み中" }
            return options.hypotheses.first { $0.id == id }?.statement ?? id
        case .mission:
            return item.sourceState.sourceMissionId
        }
    }

    private func load() async {
        loadMoreError = nil
        async let clipsTask: Void = state.loadResearchClips()
        async let associationsTask: Void = loadAssociationOptions()
        _ = await (clipsTask, associationsTask)
    }

    private func loadAssociationOptions() async {
        associationState = .loading
        do {
            associationState = .loaded(try await state.fetchResearchClipAssociationOptions())
        } catch {
            associationState = .failed("関連候補を読み込めませんでした: \(error.localizedDescription)")
        }
    }

    private func loadMore() async {
        guard !state.isLoadingMoreResearchClips else { return }
        loadMoreError = nil
        do {
            try await state.loadMoreResearchClips()
        } catch {
            loadMoreError = "調査メモの続きを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    private func sourceStateLabel(_ state: VentureResearchClipListItem.SourceState) -> String {
        if state.verificationVerdict == "failed" { return "AI検証: 不合格" }
        if !state.isCurrentDeliverable { return "修正版あり" }
        switch state.sourceReviewDecision {
        case "adopted": return "元レポート: 採用済み"
        case "rejected": return "元レポート: 却下済み"
        case "revision_requested": return "元レポート: 修正依頼済み"
        default: return "元レポート: \(state.sourceMissionStatus)"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}

struct ResearchClipEditView: View {
    let state: ProductOpsState
    let clip: VentureResearchClip
    let sourceState: VentureResearchClipListItem.SourceState?
    let associationState: ResearchClipAssociationLoadState
    let onRetryAssociations: () -> Void
    let onOpenMission: (() -> Void)?
    let onUpdated: (VentureResearchClip) -> Void
    let onArchived: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var opportunityId: String
    @State private var hypothesisId: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        state: ProductOpsState,
        clip: VentureResearchClip,
        sourceState: VentureResearchClipListItem.SourceState?,
        associationState: ResearchClipAssociationLoadState,
        onRetryAssociations: @escaping () -> Void,
        onOpenMission: (() -> Void)?,
        onUpdated: @escaping (VentureResearchClip) -> Void,
        onArchived: @escaping () -> Void
    ) {
        self.state = state
        self.clip = clip
        self.sourceState = sourceState
        self.associationState = associationState
        self.onRetryAssociations = onRetryAssociations
        self.onOpenMission = onOpenMission
        self.onUpdated = onUpdated
        self.onArchived = onArchived
        _note = State(initialValue: clip.userNote)
        _opportunityId = State(initialValue: clip.opportunityId ?? "")
        _hypothesisId = State(initialValue: clip.hypothesisId ?? "")
    }

    var body: some View {
        Form {
            Section("調査メモ") {
                Text(clip.textSnapshot)
                    .textSelection(.enabled)
                LabeledContent("知識への反映", value: "未採用メモ")
                if !clip.contextSnapshot.isEmpty {
                    LabeledContent("文脈", value: clip.contextSnapshot)
                }
                if let source = clip.sourceSnapshot.external,
                   let destination = source.destination {
                    Link(destination: destination) {
                        Label("元の情報源を開く", systemImage: "arrow.up.right.square")
                    }
                    .accessibilityHint(source.url)
                }
            }

            Section("メモ") {
                TextEditor(text: $note)
                    .frame(minHeight: 100)
                    .accessibilityLabel("調査メモ入力")
                    .accessibilityHint("2,000文字以内で補足を入力します")
                Text("\(note.count) / 2,000")
                    .font(.caption)
                    .foregroundStyle(note.count > 2_000 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            associationSection

            if let sourceState {
                Section("元レポート") {
                    LabeledContent("状態", value: sourceState.sourceMissionStatus)
                    if let verdict = sourceState.verificationVerdict {
                        LabeledContent("AI検証", value: verdict)
                    }
                    if let onOpenMission {
                        Button("元の調査結果を開く", action: onOpenMission)
                    }
                }
            } else if let onOpenMission {
                Section("元レポート") {
                    Button("元の調査結果へ戻る", action: onOpenMission)
                }
            }

            Section {
                Button("保存を解除", role: .destructive) {
                    Task { await archive() }
                }
                .disabled(isSaving)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityLabel("調査メモの保存エラー。\(errorMessage)")
                }
            }
        }
        .navigationTitle("調査メモ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(isSaving || note.count > 2_000 || !canSaveAssociation)
            }
        }
    }

    @ViewBuilder
    private var associationSection: some View {
        Section("関連付け") {
            switch associationState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("関連候補を読み込み中")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("OpportunityとHypothesisの候補を読み込み中")
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("再試行", action: onRetryAssociations)
            case .loaded(let options):
                Picker("Opportunity", selection: $opportunityId) {
                    Text("関連付けなし").tag("")
                    ForEach(options.opportunities) { opportunity in
                        Text(opportunity.title).tag(opportunity.id)
                    }
                }
                .onChange(of: opportunityId) { _, value in
                    let isValid = options.hypotheses.contains {
                        $0.id == hypothesisId && $0.opportunityId == value
                    }
                    if !isValid { hypothesisId = "" }
                }

                Picker("Hypothesis", selection: $hypothesisId) {
                    Text("関連付けなし").tag("")
                    ForEach(options.hypotheses.filter { $0.opportunityId == opportunityId }) { hypothesis in
                        Text(hypothesis.statement).tag(hypothesis.id)
                    }
                }
                .disabled(opportunityId.isEmpty)
            }
        }
    }

    private var canSaveAssociation: Bool {
        if opportunityId.isEmpty && hypothesisId.isEmpty { return true }
        guard case .loaded(let options) = associationState else { return false }
        guard options.opportunities.contains(where: { $0.id == opportunityId }) else { return false }
        return hypothesisId.isEmpty || options.hypotheses.contains {
            $0.id == hypothesisId && $0.opportunityId == opportunityId
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await state.updateResearchClip(
                clip,
                userNote: note,
                opportunityId: opportunityId.isEmpty ? nil : opportunityId,
                hypothesisId: hypothesisId.isEmpty ? nil : hypothesisId
            )
            onUpdated(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await state.archiveResearchClip(clip)
            onArchived()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
