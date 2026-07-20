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
    @State private var showsSavedClips = false

    private let kindOrder = [
        "conclusion",
        "finding",
        "supporting_evidence",
        "contradicting_evidence",
        "unknown",
        "next_question",
        "observation",
        "source",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading && candidates.isEmpty {
                HStack {
                    ProgressView()
                    Text("保存可能な項目を読み込み中")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else if candidates.isEmpty {
                fallbackContent
            } else {
                ForEach(kindOrder, id: \.self) { kind in
                    let items = candidates.filter { $0.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(items[0].label)
                                .font(.subheadline.weight(.semibold))
                            ForEach(items) { item in
                                candidateRow(item)
                            }
                        }
                    }
                }
            }

            if let loadingError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loadingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("再試行") { Task { await loadCandidates() } }
                        .font(.caption.weight(.semibold))
                }
            }

            if let operationError {
                Text(operationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: deliverableId) { await loadCandidates() }
        .sheet(isPresented: $showsSavedClips) {
            NavigationStack {
                ResearchClipListView(state: state, onOpenMission: { _ in })
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ item: VentureResearchClipCandidate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(tint(item))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.context.isEmpty {
                    Text(item.context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if mutatingItemKeys.contains(item.itemKey) {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else if item.savedClipId != nil {
                Menu {
                    Button {
                        showsSavedClips = true
                    } label: {
                        Label("保存した調査メモを開く", systemImage: "square.and.pencil")
                    }
                    if let sourceUrl = item.sourceUrl, let url = URL(string: sourceUrl) {
                        Link(destination: url) {
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
                .accessibilityLabel("\(item.label)、保存済み")
                .accessibilityHint("調査メモ一覧、情報源表示、保存解除の操作を開きます")
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
                .accessibilityLabel("\(item.label)、未保存")
                .accessibilityHint("調査メモに保存します")
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var fallbackContent: some View {
        fallbackSection("調査テーマ", [report.researchQuestion])
        fallbackSection("結論", [report.conclusion])
        fallbackSection("重要な発見", report.findings)
        fallbackSection("支持する根拠", report.supportingEvidence, tint: .green)
        fallbackSection("反例", report.contradictingEvidence, tint: .orange)
        fallbackSection("まだ分からないこと", report.unknowns)
        fallbackSection("次に確認すること", report.nextQuestions)
        fallbackSection("情報源", report.sources)
    }

    @ViewBuilder
    private func fallbackSection(_ title: String, _ items: [String], tint: Color = .primary) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tint(_ item: VentureResearchClipCandidate) -> Color {
        switch item.relation {
        case "supports": return .green
        case "contradicts": return .orange
        default: return .primary
        }
    }

    private func loadCandidates() async {
        isLoading = true
        loadingError = nil
        defer { isLoading = false }
        do {
            candidates = try await state.fetchResearchClipCandidates(deliverableId: deliverableId).items
        } catch {
            loadingError = "調査メモ候補を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    private func save(_ item: VentureResearchClipCandidate) async {
        mutatingItemKeys.insert(item.itemKey)
        operationError = nil
        defer { mutatingItemKeys.remove(item.itemKey) }
        do {
            let clip = try await state.saveResearchClip(deliverableId: deliverableId, itemKey: item.itemKey)
            updateCandidate(item.itemKey) { candidate in
                candidate.savedClipId = clip.id
                candidate.savedClipVersion = clip.version
            }
        } catch {
            operationError = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    private func archive(_ item: VentureResearchClipCandidate) async {
        guard let clipId = item.savedClipId, let version = item.savedClipVersion else { return }
        mutatingItemKeys.insert(item.itemKey)
        operationError = nil
        defer { mutatingItemKeys.remove(item.itemKey) }
        do {
            try await state.archiveResearchClip(clipId: clipId, expectedVersion: version)
            updateCandidate(item.itemKey) { candidate in
                candidate.savedClipId = nil
                candidate.savedClipVersion = nil
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
