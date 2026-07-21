import SwiftUI

struct ResearchReportItemsView: View {
    let state: ProductOpsState
    let deliverableId: String
    let report: VentureResearchReportDeliverable

    @State private var candidates: [VentureResearchClipCandidate] = []
    @State private var isLoading = false
    @State private var loadingError: String?
    @State private var operationError: String?
    @State private var mutatingItemKeys: Set<String> = []
    @State private var editingClip: VentureResearchClip?
    @State private var associationState: ResearchClipAssociationLoadState = .loading

    private let kindOrder = VentureResearchReportItemKind.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading && candidates.isEmpty {
                HStack {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("保存可能な項目を読み込み中")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("調査メモ候補を読み込み中")
            } else if let loadingError, candidates.isEmpty {
                loadErrorView(loadingError)
            } else if candidates.isEmpty {
                ContentUnavailableView(
                    "保存可能な項目はありません",
                    systemImage: "bookmark.slash",
                    description: Text("この調査結果には構造化された項目がありません。")
                )
            } else {
                ForEach(kindOrder, id: \.self) { kind in
                    let items = candidates.filter { $0.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.label)
                                .font(.subheadline.weight(.semibold))
                            ForEach(items) { item in
                                candidateRow(item)
                            }
                        }
                    }
                }
            }

            if let loadingError, !candidates.isEmpty {
                loadErrorView(loadingError)
            }

            if case .failed(let message) = associationState {
                associationErrorView(message)
            }

            if let operationError {
                Text(operationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("調査メモの操作エラー。\(operationError)")
            }
        }
        .task(id: deliverableId) { await load() }
        .sheet(item: $editingClip) { clip in
            NavigationStack {
                ResearchClipEditView(
                    state: state,
                    clip: clip,
                    sourceState: nil,
                    associationState: associationState,
                    onRetryAssociations: {
                        Task { await loadAssociationOptions() }
                    },
                    onOpenMission: nil,
                    onUpdated: { updated in
                        updateCandidate(updated.itemKey) { candidate in
                            candidate.savedClip = updated
                        }
                    },
                    onArchived: {
                        updateCandidate(clip.itemKey) { candidate in
                            candidate.savedClip = nil
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ item: VentureResearchClipCandidate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(tint(item.relation))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.context.isEmpty {
                    Text(item.context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let source = item.sourceSnapshot.external,
                   let destination = ResearchSourceDestination(source: source) {
                    ResearchSourceLinkButton(destination: destination) {
                        Label("元の情報源", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("元の情報源を開く")
                    .accessibilityHint(source.url)
                }
            }
            Spacer(minLength: 8)
            if mutatingItemKeys.contains(item.itemKey) {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("\(item.kind.label)、保存中")
            } else if let savedClip = item.savedClip {
                Menu {
                    Button {
                        editingClip = savedClip
                    } label: {
                        Label("調査メモを編集", systemImage: "square.and.pencil")
                    }
                    if let source = item.sourceSnapshot.external,
                       let destination = ResearchSourceDestination(source: source) {
                        ResearchSourceLinkButton(destination: destination) {
                            Label("元の情報源を開く", systemImage: "arrow.up.right.square")
                        }
                    }
                    Button(role: .destructive) {
                        Task { await archive(item) }
                    } label: {
                        Label("保存を解除", systemImage: "bookmark.slash")
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(item.kind.label)、保存済み")
                .accessibilityHint("調査メモの編集、情報源表示、保存解除の操作を開きます")
            } else {
                Button {
                    Task { await save(item) }
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.kind.label)、未保存")
                .accessibilityHint("調査メモに保存します")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private func tint(_ relation: VentureResearchReportRelation) -> Color {
        switch relation {
        case .supports: return .green
        case .contradicts: return .orange
        case .context, .unrelated: return .primary
        }
    }

    @ViewBuilder
    private func loadErrorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Button("調査メモ候補を再読み込み") {
                Task { await loadCandidates() }
            }
            .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func associationErrorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Button("関連候補を再読み込み") {
                Task { await loadAssociationOptions() }
            }
            .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .contain)
    }

    private func load() async {
        async let candidatesTask: Void = loadCandidates()
        async let associationsTask: Void = loadAssociationOptions()
        _ = await (candidatesTask, associationsTask)
    }

    private func loadCandidates() async {
        isLoading = true
        loadingError = nil
        defer { isLoading = false }
        do {
            let payload = try await state.fetchResearchClipCandidates(deliverableId: deliverableId)
            let reportItemIds = Set(report.items.map(\.id))
            let candidateItemIds = Set(payload.items.map(\.itemKey))
            guard candidateItemIds == reportItemIds else {
                loadingError = "調査メモ候補が表示中の調査結果と一致しません。再読み込みしてください。"
                candidates = []
                return
            }
            candidates = payload.items
        } catch {
            loadingError = "調査メモ候補を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    private func loadAssociationOptions() async {
        associationState = .loading
        do {
            associationState = .loaded(try await state.fetchResearchClipAssociationOptions())
        } catch {
            associationState = .failed("関連候補を読み込めませんでした: \(error.localizedDescription)")
        }
    }

    private func save(_ item: VentureResearchClipCandidate) async {
        guard !mutatingItemKeys.contains(item.itemKey) else { return }
        mutatingItemKeys.insert(item.itemKey)
        operationError = nil
        defer { mutatingItemKeys.remove(item.itemKey) }
        do {
            let clip = try await state.saveResearchClip(deliverableId: deliverableId, itemKey: item.itemKey)
            updateCandidate(item.itemKey) { candidate in
                candidate.savedClip = clip
            }
        } catch {
            operationError = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    private func archive(_ item: VentureResearchClipCandidate) async {
        guard let clip = item.savedClip,
              !mutatingItemKeys.contains(item.itemKey) else { return }
        mutatingItemKeys.insert(item.itemKey)
        operationError = nil
        defer { mutatingItemKeys.remove(item.itemKey) }
        do {
            try await state.archiveResearchClip(clipId: clip.id, expectedVersion: clip.version)
            updateCandidate(item.itemKey) { candidate in
                candidate.savedClip = nil
            }
        } catch {
            operationError = "保存を解除できませんでした: \(error.localizedDescription)"
        }
    }

    private func updateCandidate(
        _ itemKey: String,
        change: (inout VentureResearchClipCandidate) -> Void
    ) {
        guard let index = candidates.firstIndex(where: { $0.itemKey == itemKey }) else { return }
        change(&candidates[index])
    }
}
