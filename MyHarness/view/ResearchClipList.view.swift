import SwiftUI

struct ResearchClipListView: View {
    let state: ProductOpsState
    let onOpenMission: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var grouping: Grouping = .savedAt
    @State private var associationOptions: VentureResearchClipAssociationOptions?
    @State private var selectedItem: VentureResearchClipListItem?

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
                    List {
                        ForEach(groupedItems(page.items), id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.items) { item in
                                    researchClipRow(item)
                                }
                            }
                        }
                        if page.nextCursor != nil {
                            Button("さらに表示") {
                                Task { await state.loadMoreResearchClips() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .listStyle(.plain)
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
                    associationOptions: associationOptions,
                    onOpenMission: {
                        selectedItem = nil
                        onOpenMission(item.sourceState.sourceMissionId)
                    },
                    onUpdated: { _ in },
                    onArchived: {}
                )
            }
        }
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
                    Text(itemKindLabel(item.clip.itemKind))
                    if let relation = item.clip.relation {
                        Text(relationLabel(relation))
                    }
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
        .accessibilityLabel("\(itemKindLabel(item.clip.itemKind))、保存済み。\(item.clip.textSnapshot)")
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
            return associationOptions?.opportunities.first { $0.id == id }?.title ?? id
        case .hypothesis:
            guard let id = item.clip.hypothesisId else { return "未関連付け" }
            return associationOptions?.hypotheses.first { $0.id == id }?.statement ?? id
        case .mission:
            return item.sourceState.sourceMissionId
        }
    }

    private func load() async {
        async let clips: Void = state.loadResearchClips()
        async let options = try? state.fetchResearchClipAssociationOptions()
        _ = await clips
        associationOptions = await options
    }

    private func itemKindLabel(_ kind: String) -> String {
        switch kind {
        case "conclusion": return "結論"
        case "finding": return "重要な発見"
        case "supporting_evidence": return "支持する根拠"
        case "contradicting_evidence": return "反例"
        case "unknown": return "まだ分からないこと"
        case "next_question": return "次に確認すること"
        case "source": return "情報源"
        default: return "個別の観測結果"
        }
    }

    private func relationLabel(_ relation: String) -> String {
        switch relation {
        case "supports": return "支持"
        case "contradicts": return "反例"
        default: return "文脈"
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
    let associationOptions: VentureResearchClipAssociationOptions?
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
        associationOptions: VentureResearchClipAssociationOptions?,
        onOpenMission: (() -> Void)?,
        onUpdated: @escaping (VentureResearchClip) -> Void,
        onArchived: @escaping () -> Void
    ) {
        self.state = state
        self.clip = clip
        self.sourceState = sourceState
        self.associationOptions = associationOptions
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
                if !clip.contextSnapshot.isEmpty {
                    LabeledContent("採用理由", value: clip.contextSnapshot)
                }
                if let url = clip.sourceUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Label("元の情報源を開く", systemImage: "arrow.up.right.square")
                    }
                }
            }

            Section("メモ") {
                TextEditor(text: $note)
                    .frame(minHeight: 100)
            }

            Section("関連付け") {
                Picker("Opportunity", selection: $opportunityId) {
                    Text("関連付けなし").tag("")
                    ForEach(associationOptions?.opportunities ?? []) { opportunity in
                        Text(opportunity.title).tag(opportunity.id)
                    }
                }
                .onChange(of: opportunityId) { _, value in
                    let isValid = associationOptions?.hypotheses.contains {
                        $0.id == hypothesisId && $0.opportunityId == value
                    } ?? false
                    if !isValid { hypothesisId = "" }
                }

                Picker("Hypothesis", selection: $hypothesisId) {
                    Text("関連付けなし").tag("")
                    ForEach((associationOptions?.hypotheses ?? []).filter { $0.opportunityId == opportunityId }) { hypothesis in
                        Text(hypothesis.statement).tag(hypothesis.id)
                    }
                }
                .disabled(opportunityId.isEmpty)
            }

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
                    Text(errorMessage).foregroundStyle(.red)
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
                    .disabled(isSaving || note.count > 2_000)
            }
        }
    }

    private func save() async {
        isSaving = true
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
        isSaving = true
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
