import SwiftUI

@MainActor
struct VenturePolicyView: View {
    let state: ProductOpsState
    @State private var editor: VenturePolicyEditor?

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle("事業方針")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let policy = state.policy {
                    Menu {
                        Button("事業方針を編集", systemImage: "square.and.pencil") {
                            editor = .policyText(policy)
                        }
                        Button("推薦設定を編集", systemImage: "slider.horizontal.3") {
                            editor = .recommendationSettings(policy)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("事業方針メニュー")
                }
            }
        }
        .refreshable {
            await state.loadPolicyIfPossible()
        }
        .task {
            await state.loadPolicyIfPossible()
            await state.loadNextActions()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = state.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            }
        }
        .sheet(item: $editor) { selectedEditor in
            NavigationStack {
                switch selectedEditor {
                case .policyText(let policy):
                    VenturePolicyTextEditSheet(state: state, policy: policy) { revision in
                        editor = .revision(revision)
                    }
                case .recommendationSettings(let policy):
                    VentureRecommendationSettingsEditSheet(state: state, policy: policy) { revision in
                        editor = .revision(revision)
                    }
                case .revision(let revision):
                    VenturePolicyRevisionReviewView(state: state, revision: revision)
                case .revisionList(let items):
                    VenturePolicyRevisionListView(state: state, items: items) { revision in
                        editor = .revision(revision)
                    }
                }
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
                message: "次にやるタブのメニューからログインしてください。"
            )
            .listRowSeparator(.hidden)
        } else {
            switch state.policyState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            case .failed(let message):
                ContentUnavailableView {
                    Label("事業方針を読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .listRowSeparator(.hidden)
            case .loaded(let policy):
                Section {
                    ProductOpsMarkdownView(markdown: policy.policyText)
                        .padding(.vertical, 4)
                } header: {
                    sectionHeader("事業方針") {
                        editor = .policyText(policy)
                    }
                } footer: {
                    Text("AIへの参考文脈です。推薦条件や評価設定には自動変換されません。")
                }

                Section {
                    LabeledContent("事業段階", value: stageLabel(policy.stage))
                    valueRows(label: "現在の目的", values: policy.objectives.map { objectiveLabel($0, policy: policy) })
                    valueRows(label: "対象顧客", values: policy.targetSegments.map(\.label))
                    valueRows(label: "現在のFocus", values: policy.focusAreas)
                    valueRows(label: "商業仮説", values: policy.commercialHypotheses)
                    LabeledContent("最大推薦件数", value: "\(policy.maxRecommendations)")

                    DisclosureGroup("評価基準 \(policy.lenses.count)件") {
                        ForEach(policy.lenses) { lens in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(lens.label)
                                Text("重み \(lens.weight.formatted()) ・ \(directionLabel(lens.direction))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(lens.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    DisclosureGroup("Hard Gate \(policy.hardGates.count)件") {
                        ForEach(policy.hardGates) { gate in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(gate.label)
                                Text(gate.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }

                    DisclosureGroup("調査・提供時の制約") {
                        valueRows(label: "調査", values: policy.researchGuardrails)
                        valueRows(label: "実装・提供", values: policy.deliveryGuardrails)
                        valueRows(label: "システム安全制約", values: policy.systemSafetyConstraints)
                    }
                } header: {
                    sectionHeader("推薦設定") {
                        editor = .recommendationSettings(policy)
                    }
                } footer: {
                    Text("提案生成、候補の除外、採点、推薦順位に使用されます。")
                }

                if let currentView = policy.currentView {
                    Section("現在の事業認識") {
                        Text(currentView)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if policy.pendingPolicyChangeCount > 0 {
                    Section {
                        Button {
                            Task { await openPendingPolicyRevision() }
                        } label: {
                            HStack {
                                Text("確認待ちの変更")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(policy.pendingPolicyChangeCount)件")
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, edit: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("\(title)を編集")
        }
    }

    @ViewBuilder
    private func valueRows(label: String, values: [String]) -> some View {
        if values.isEmpty {
            LabeledContent(label, value: "なし")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "exploration": "探索"
        case "validation": "検証"
        case "delivery": "提供準備"
        case "launch": "公開"
        case "growth": "成長"
        default: stage
        }
    }

    private func objectiveLabel(_ key: String, policy: VenturePolicy) -> String {
        policy.objectiveDefinitions.first { $0.key == key }?.label ?? key
    }

    private func directionLabel(_ direction: String) -> String {
        direction == "higher_is_better" ? "高いほど優先" : "低いほど優先"
    }

    private func openPendingPolicyRevision() async {
        let items = state.missionSummaryItems.filter {
            $0.deliverableKind == "knowledge_change" && $0.status == "awaiting_review"
        }
        guard !items.isEmpty else {
            state.message = "確認待ちの方針変更を取得できませんでした"
            return
        }
        guard items.count == 1, let item = items.first else {
            editor = .revisionList(items)
            return
        }
        do {
            editor = .revision(try await state.fetchPolicyRevision(missionId: item.id))
        } catch {
            state.message = "方針変更を読み込めませんでした: \(error.localizedDescription)"
        }
    }
}

private enum VenturePolicyEditor: Identifiable {
    case policyText(VenturePolicy)
    case recommendationSettings(VenturePolicy)
    case revision(VenturePolicyRevisionDetail)
    case revisionList([VentureMissionSummaryItem])

    var id: String {
        switch self {
        case .policyText(let policy): "text-\(policy.policyTextVersion)"
        case .recommendationSettings(let policy): "settings-\(policy.strategyVersionId)-\(policy.decisionFrameVersionId)"
        case .revision(let revision): "revision-\(revision.missionId)-\(revision.revisionHash)"
        case .revisionList(let items): "revision-list-\(items.map(\.id).joined(separator: "-"))"
        }
    }
}

private struct VenturePolicyRevisionListView: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let items: [VentureMissionSummaryItem]
    let onSelect: (VenturePolicyRevisionDetail) -> Void
    @State private var loadingMissionId: String?
    @State private var errorMessage: String?

    var body: some View {
        List(items) { item in
            Button {
                Task { await open(item) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(item.updatedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if loadingMissionId == item.id {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(loadingMissionId != nil)
            .accessibilityLabel("\(item.title)、方針変更の差分を確認")
        }
        .navigationTitle("確認待ちの方針変更")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .alert("方針変更を読み込めません", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func open(_ item: VentureMissionSummaryItem) async {
        loadingMissionId = item.id
        defer { loadingMissionId = nil }
        do {
            onSelect(try await state.fetchPolicyRevision(missionId: item.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VenturePolicyTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let onCreated: (VenturePolicyRevisionDetail) -> Void
    @State private var policyText: String
    @State private var reason = ""
    private let originalText: String

    init(
        state: ProductOpsState,
        policy: VenturePolicy,
        onCreated: @escaping (VenturePolicyRevisionDetail) -> Void
    ) {
        self.state = state
        self.onCreated = onCreated
        originalText = policy.policyText
        _policyText = State(initialValue: policy.policyText)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $policyText)
                    .font(.body.monospaced())
                    .frame(minHeight: 460)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("事業方針Markdown")
            } header: {
                Text("Markdown")
            } footer: {
                Text("文章はそのまま保存されます。見出しを変えても推薦設定は変わりません。")
            }

            Section("変更理由") {
                TextField("変更した理由", text: $reason, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("事業方針を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        if let revision = await state.createPolicyTextRevision(
                            policyText: policyText,
                            reason: normalizedReason
                        ) {
                            onCreated(revision)
                        }
                    }
                } label: {
                    state.isSavingPolicy ? AnyView(ProgressView()) : AnyView(Text("変更内容を確認"))
                }
                .disabled(state.isSavingPolicy || policyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalizedReason.isEmpty || policyText == originalText)
            }
        }
    }

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct VentureRecommendationSettingsEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    let policy: VenturePolicy
    let onCreated: (VenturePolicyRevisionDetail) -> Void

    @State private var mission: String
    @State private var targetSegments: [VenturePolicyTargetSegment]
    @State private var desiredOutcomes: [String]
    @State private var commercialHypotheses: [String]
    @State private var focusAreas: [String]
    @State private var exclusions: [String]
    @State private var researchGuardrails: [String]
    @State private var deliveryGuardrails: [String]
    @State private var stage: String
    @State private var objectiveIds: Set<String>
    @State private var lenses: [VenturePolicyDecisionLens]
    @State private var hardGates: [VenturePolicyHardGate]
    @State private var reason = ""

    init(
        state: ProductOpsState,
        policy: VenturePolicy,
        onCreated: @escaping (VenturePolicyRevisionDetail) -> Void
    ) {
        self.state = state
        self.policy = policy
        self.onCreated = onCreated
        _mission = State(initialValue: policy.mission)
        _targetSegments = State(initialValue: policy.targetSegments)
        _desiredOutcomes = State(initialValue: policy.desiredOutcomes)
        _commercialHypotheses = State(initialValue: policy.commercialHypotheses)
        _focusAreas = State(initialValue: policy.focusAreas)
        _exclusions = State(initialValue: policy.exclusions)
        _researchGuardrails = State(initialValue: policy.researchGuardrails)
        _deliveryGuardrails = State(initialValue: policy.deliveryGuardrails)
        _stage = State(initialValue: policy.stage)
        _objectiveIds = State(initialValue: Set(policy.objectives))
        _lenses = State(initialValue: policy.lenses)
        _hardGates = State(initialValue: policy.hardGates)
    }

    var body: some View {
        Form {
            Section("事業の構造") {
                TextField("目的", text: $mission, axis: .vertical)
                    .lineLimit(2...6)
                Picker("事業段階", selection: $stage) {
                    Text("探索").tag("exploration")
                    Text("検証").tag("validation")
                    Text("提供準備").tag("delivery")
                    Text("公開").tag("launch")
                    Text("成長").tag("growth")
                }
            }

            Section("対象顧客") {
                ForEach(Array(targetSegments.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("キー", text: $targetSegments[index].key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("表示名", text: $targetSegments[index].label)
                        TextField("説明", text: $targetSegments[index].description, axis: .vertical)
                            .lineLimit(2...5)
                        if targetSegments.count > 1 {
                            Button("削除", role: .destructive) { targetSegments.remove(at: index) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button("対象顧客を追加", systemImage: "plus") {
                    targetSegments.append(.init(key: "", label: "", description: ""))
                }
            }

            EditableStringListSection(title: "期待する成果", values: $desiredOutcomes)
            EditableStringListSection(title: "商業仮説", values: $commercialHypotheses)
            EditableStringListSection(title: "現在のFocus", values: $focusAreas)
            EditableStringListSection(title: "除外事項", values: $exclusions)

            Section("現在の目的") {
                ForEach(policy.objectiveDefinitions) { definition in
                    Toggle(isOn: objectiveBinding(definition.key)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.label)
                            Text(definition.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ForEach(Array(lenses.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lenses[index].label)
                            .font(.headline)
                        Text(lenses[index].description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("重み", value: $lenses[index].weight, format: .number)
                            .keyboardType(.decimalPad)
                        Picker("評価方向", selection: $lenses[index].direction) {
                            Text("高いほど優先").tag("higher_is_better")
                            Text("低いほど優先").tag("lower_is_better")
                        }
                        Toggle("必須", isOn: $lenses[index].required)
                        Button("評価基準から外す", role: .destructive) { lenses.remove(at: index) }
                    }
                    .padding(.vertical, 4)
                }
                Menu("評価基準を追加", systemImage: "plus") {
                    ForEach(availableLensDefinitions) { definition in
                        Button(definition.label) { addLens(definition) }
                    }
                }
                .disabled(availableLensDefinitions.isEmpty)
            } header: {
                HStack {
                    Text("評価基準")
                    Spacer()
                    Text("合計 \(weightTotal.formatted())")
                        .foregroundColor(weightTotal == 100 ? .secondary : .red)
                }
            } footer: {
                Text("重みの合計を100にしてください。")
            }

            Section("Hard Gate") {
                ForEach(policy.hardGateDefinitions) { definition in
                    Toggle(isOn: hardGateBinding(definition)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.label)
                            Text(definition.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                LabeledContent("一度に表示する件数", value: "1")
            } header: {
                Text("最大推薦件数")
            } footer: {
                Text("現在の操作盤は、最も重要な一手だけを表示します。")
            }

            EditableStringListSection(title: "調査時の制約", values: $researchGuardrails)
            EditableStringListSection(title: "実装・提供時の制約", values: $deliveryGuardrails)

            Section("変更理由") {
                TextField("推薦設定を変える理由", text: $reason, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("推薦設定を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        let strategy = VenturePolicyStrategySettingsRequest(
                            mission: mission.trimmingCharacters(in: .whitespacesAndNewlines),
                            targetSegments: normalizedSegments,
                            desiredOutcomes: normalized(desiredOutcomes),
                            commercialHypotheses: normalized(commercialHypotheses),
                            focusAreas: normalized(focusAreas),
                            exclusions: normalized(exclusions),
                            researchGuardrails: normalized(researchGuardrails),
                            deliveryGuardrails: normalized(deliveryGuardrails)
                        )
                        let frame = VenturePolicyDecisionFrameSettingsRequest(
                            stage: stage,
                            objectiveIds: objectiveIds.sorted(),
                            lenses: lenses,
                            hardGates: hardGates,
                            maxRecommendations: 1
                        )
                        if let revision = await state.createRecommendationSettingsRevision(
                            strategy: strategy,
                            decisionFrame: frame,
                            reason: normalizedReason
                        ) {
                            onCreated(revision)
                        }
                    }
                } label: {
                    state.isSavingPolicy ? AnyView(ProgressView()) : AnyView(Text("変更内容を確認"))
                }
                .disabled(!canSave)
            }
        }
    }

    private var weightTotal: Double { lenses.reduce(0) { $0 + $1.weight } }

    private var normalizedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !state.isSavingPolicy
            && !mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !targetSegments.isEmpty
            && targetSegments.allSatisfy {
                !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            && Set(normalizedSegments.map(\.key)).count == normalizedSegments.count
            && !lenses.isEmpty
            && abs(weightTotal - 100) < 0.0001
            && !normalizedReason.isEmpty
            && hasSettingsChanges
    }

    private var hasSettingsChanges: Bool {
        mission.trimmingCharacters(in: .whitespacesAndNewlines) != policy.mission
            || normalizedSegments != policy.targetSegments
            || normalized(desiredOutcomes) != policy.desiredOutcomes
            || normalized(commercialHypotheses) != policy.commercialHypotheses
            || normalized(focusAreas) != policy.focusAreas
            || normalized(exclusions) != policy.exclusions
            || normalized(researchGuardrails) != policy.researchGuardrails
            || normalized(deliveryGuardrails) != policy.deliveryGuardrails
            || stage != policy.stage
            || objectiveIds != Set(policy.objectives)
            || lenses != policy.lenses
            || hardGates != policy.hardGates
    }

    private var normalizedSegments: [VenturePolicyTargetSegment] {
        targetSegments.map {
            .init(
                key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private var availableLensDefinitions: [VenturePolicyDecisionLensDefinition] {
        let keys = Set(lenses.map(\.key))
        return policy.decisionLensDefinitions.filter { !keys.contains($0.key) }
    }

    private func addLens(_ definition: VenturePolicyDecisionLensDefinition) {
        lenses.append(.init(
            key: definition.key,
            label: definition.label,
            weight: 1,
            direction: definition.direction,
            required: false,
            description: definition.description
        ))
    }

    private func objectiveBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { objectiveIds.contains(key) },
            set: { enabled in
                if enabled { objectiveIds.insert(key) } else { objectiveIds.remove(key) }
            }
        )
    }

    private func hardGateBinding(_ definition: VenturePolicyHardGateDefinition) -> Binding<Bool> {
        Binding(
            get: { hardGates.contains { $0.key == definition.key } },
            set: { enabled in
                hardGates.removeAll { $0.key == definition.key }
                if enabled {
                    hardGates.append(.init(
                        key: definition.key,
                        label: definition.label,
                        description: definition.description,
                        parameters: [:]
                    ))
                }
            }
        )
    }

    private func normalized(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct VenturePolicyRevisionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    @State private var revision: VenturePolicyRevisionDetail
    @State private var feedbackAction: VenturePolicyRevisionFeedbackAction?
    @State private var feedback = ""
    @State private var isConfirmingAdoption = false
    @State private var errorMessage: String?

    init(state: ProductOpsState, revision: VenturePolicyRevisionDetail) {
        self.state = state
        _revision = State(initialValue: revision)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                statusSection

                if revision.policyTextDiff.before != revision.policyTextDiff.after {
                    policyTextDiffSection
                }

                if !revision.structuredChanges.isEmpty {
                    structuredChangesSection
                }

                impactPreviewSection

                reviewContextSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .navigationTitle("方針変更を確認")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .confirmationDialog(
            "方針変更を反映しますか？",
            isPresented: $isConfirmingAdoption,
            titleVisibility: .visible
        ) {
            Button("採用して反映") {
                submit(decision: "adopted", feedback: "差分を確認して採用")
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(adoptionConfirmationMessage)
        }
        .sheet(item: $feedbackAction) { action in
            NavigationStack {
                Form {
                    Section(action.prompt) {
                        TextEditor(text: $feedback)
                            .frame(minHeight: 180)
                    }
                }
                .navigationTitle(action.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            feedback = ""
                            feedbackAction = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action.submitLabel) {
                            let normalized = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                            feedbackAction = nil
                            submit(decision: action.decision, feedback: normalized)
                        }
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .alert("操作できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(applicationLabel, systemImage: applicationIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(applicationTint)
                Spacer()
                Text(riskLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(revision.summary)
                .font(.title3.weight(.semibold))

            if revision.isStale {
                Label("基準の方針が更新されたため、この候補は採用できません。", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                ForEach(revision.staleReasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var policyTextDiffSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("事業方針本文")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(revision.policyTextDiff.hunks) { hunk in
                    Text("@@ -\(hunk.oldStart),\(hunk.oldLineCount) +\(hunk.newStart),\(hunk.newLineCount) @@")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08))
                    ForEach(hunk.lines) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(diffLineNumber(line))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                            Text(diffPrefix(line.kind))
                                .font(.body.monospaced())
                                .foregroundStyle(diffTint(line.kind))
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(diffBackground(line.kind))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
    }

    private var structuredChangesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("推薦設定")
                .font(.headline)
            ForEach(revision.structuredChanges) { change in
                VStack(alignment: .leading, spacing: 8) {
                    Text(change.label)
                        .font(.subheadline.weight(.semibold))
                    comparisonBlock(label: "変更前", lines: change.before, tint: .red)
                    comparisonBlock(label: "変更後", lines: change.after, tint: .green)
                    if !change.removed.isEmpty {
                        changeLines(label: "削除", values: change.removed, tint: .red)
                    }
                    if !change.added.isEmpty {
                        changeLines(label: "追加", values: change.added, tint: .green)
                    }
                    if change.reordered {
                        Label("並び順を変更", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var impactPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("反映時の影響")
                .font(.headline)
            impactRow("おすすめ", count: revision.impactPreview.staleProposalCount, suffix: "件を古い方針扱いにする")
            impactRow("判断項目", count: revision.impactPreview.supersededAgendaItemCount, suffix: "件を終了する")
            impactRow("推薦集合", count: revision.impactPreview.supersededRecommendationSetCount, suffix: "件を更新する")
            impactRow("事業認識", count: revision.impactPreview.supersededSynthesisCount, suffix: "件を更新する")
        }
    }

    private var reviewContextSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailText("変更理由", revision.rationale)
            detailText("期待する影響", revision.expectedImpact)
            if !revision.contraryEvidence.isEmpty {
                textSection("反対材料", values: revision.contraryEvidence)
            }
            if let summary = revision.consultationSummary, !summary.isEmpty {
                detailText("相談の要約", summary)
            }
            if !revision.sourceRefs.isEmpty {
                textSection(
                    "根拠",
                    values: revision.sourceRefs.map { "\($0.kind) / \($0.relation) / \($0.id)" }
                )
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if revision.canReject {
                actionButton("却下", systemImage: "xmark", tint: .red) {
                    feedback = ""
                    feedbackAction = .reject
                }
            }
            if revision.canRequestRevision && !revision.isStale {
                actionButton("修正", systemImage: "arrow.uturn.backward", tint: .orange) {
                    feedback = ""
                    feedbackAction = .revise
                }
            }
            if revision.canAdopt && !revision.isStale {
                actionButton("採用", systemImage: "checkmark", tint: .green) {
                    isConfirmingAdoption = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(VenturePolicyTranslucentButtonStyle(tint: tint))
        .disabled(state.isUpdatingMission)
    }

    private func comparisonBlock(label: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if lines.isEmpty {
                Text("なし")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func changeLines(label: String, values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(values, id: \.self) { value in
                Text("• \(value)")
                    .font(.caption)
            }
        }
    }

    private func impactRow(_ label: String, count: Int, suffix: String) -> some View {
        LabeledContent(label) {
            Text("\(count)\(suffix)")
                .foregroundStyle(count == 0 ? .secondary : .primary)
        }
    }

    private var adoptionConfirmationMessage: String {
        let preview = revision.impactPreview
        return "この変更により、おすすめ\(preview.staleProposalCount)件、判断項目\(preview.supersededAgendaItemCount)件を古い方針扱いにし、新しい方針で再評価します。"
    }

    private func detailText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textSection(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
            ForEach(values, id: \.self) { value in
                HStack(alignment: .top, spacing: 7) {
                    Text("•")
                    Text(value)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func submit(decision: String, feedback: String) {
        Task {
            do {
                revision = try await state.reviewPolicyRevision(
                    detail: revision,
                    decision: decision,
                    feedback: feedback
                )
                if decision != "revision_requested" || revision.status == "awaiting_external_input" {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var applicationLabel: String {
        switch revision.applicationStatus {
        case "pending_apply": "反映待ち"
        case "applied": "反映済み"
        case "apply_failed": "反映失敗"
        case "stale": "古い候補"
        default: "確認待ち"
        }
    }

    private var applicationIcon: String {
        switch revision.applicationStatus {
        case "applied": "checkmark.circle.fill"
        case "apply_failed", "stale": "exclamationmark.triangle.fill"
        case "pending_apply": "clock.fill"
        default: "doc.text.magnifyingglass"
        }
    }

    private var applicationTint: Color {
        switch revision.applicationStatus {
        case "applied": .green
        case "apply_failed", "stale": .red
        case "pending_apply": .orange
        default: .secondary
        }
    }

    private var riskLabel: String {
        switch revision.risk {
        case "critical": "重大"
        case "high": "高リスク"
        default: "中リスク"
        }
    }

    private func diffPrefix(_ kind: String) -> String {
        switch kind {
        case "added": "+"
        case "removed": "−"
        default: " "
        }
    }

    private func diffLineNumber(_ line: VenturePolicyDiffLine) -> String {
        "\(line.oldLineNumber.map(String.init) ?? " ")  \(line.newLineNumber.map(String.init) ?? " ")"
    }

    private func diffTint(_ kind: String) -> Color {
        switch kind {
        case "added": .green
        case "removed": .red
        default: .secondary
        }
    }

    private func diffBackground(_ kind: String) -> Color {
        switch kind {
        case "added": Color.green.opacity(0.09)
        case "removed": Color.red.opacity(0.09)
        default: Color.clear
        }
    }

}

struct VenturePolicyRevisionLoaderView: View {
    let state: ProductOpsState
    let missionId: String
    @State private var revision: VenturePolicyRevisionDetail?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let revision {
                    VenturePolicyRevisionReviewView(state: state, revision: revision)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("方針変更を読み込めません", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("再試行") { Task { await load() } }
                    }
                } else {
                    ProgressView("差分を読み込んでいます")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            revision = try await state.fetchPolicyRevision(missionId: missionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum VenturePolicyRevisionFeedbackAction: String, Identifiable {
    case revise
    case reject

    var id: String { rawValue }
    var decision: String { self == .revise ? "revision_requested" : "rejected" }
    var title: String { self == .revise ? "修正を依頼" : "方針変更案を却下" }
    var prompt: String { self == .revise ? "直してほしい内容" : "却下する理由" }
    var submitLabel: String { self == .revise ? "修正を依頼" : "却下する" }
}

private struct VenturePolicyTranslucentButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(configuration.isPressed ? 0.55 : 0.25), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct EditableStringListSection: View {
    let title: String
    @Binding var values: [String]

    var body: some View {
        Section(title) {
            ForEach(Array(values.indices), id: \.self) { index in
                HStack(alignment: .top) {
                    TextField(title, text: $values[index], axis: .vertical)
                        .lineLimit(1...5)
                    Button(role: .destructive) {
                        values.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title)を削除")
                }
            }
            Button("追加", systemImage: "plus") { values.append("") }
        }
    }
}
