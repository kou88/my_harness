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
        }
        .safeAreaInset(edge: .bottom) {
            if let message = state.message {
                ProductOpsMessageBar(text: message, systemImage: "info.circle")
            }
        }
        .sheet(item: $editor) { editor in
            NavigationStack {
                switch editor {
                case .policyText(let policy):
                    VenturePolicyTextEditSheet(state: state, policy: policy)
                case .recommendationSettings(let policy):
                    VentureRecommendationSettingsEditSheet(state: state, policy: policy)
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
                        LabeledContent("確認待ちの変更") {
                            Text("\(policy.pendingPolicyChangeCount)件")
                                .monospacedDigit()
                                .foregroundStyle(.orange)
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
}

private enum VenturePolicyEditor: Identifiable {
    case policyText(VenturePolicy)
    case recommendationSettings(VenturePolicy)

    var id: String {
        switch self {
        case .policyText(let policy): "text-\(policy.policyTextVersion)"
        case .recommendationSettings(let policy): "settings-\(policy.strategyVersionId)-\(policy.decisionFrameVersionId)"
        }
    }
}

private struct VenturePolicyTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    @State private var policyText: String
    @State private var reason = ""
    private let originalText: String

    init(state: ProductOpsState, policy: VenturePolicy) {
        self.state = state
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
                        if await state.updatePolicyText(policyText: policyText, reason: normalizedReason) != nil {
                            dismiss()
                        }
                    }
                } label: {
                    state.isSavingPolicy ? AnyView(ProgressView()) : AnyView(Text("保存"))
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

    init(state: ProductOpsState, policy: VenturePolicy) {
        self.state = state
        self.policy = policy
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
                        if await state.updateRecommendationSettings(
                            strategy: strategy,
                            decisionFrame: frame,
                            commercialHypotheses: normalized(commercialHypotheses),
                            reason: normalizedReason
                        ) != nil {
                            dismiss()
                        }
                    }
                } label: {
                    state.isSavingPolicy ? AnyView(ProgressView()) : AnyView(Text("保存"))
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
