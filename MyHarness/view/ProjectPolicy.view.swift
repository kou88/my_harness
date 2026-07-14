import SwiftUI

@MainActor
struct ProjectPolicyView: View {
    let state: ProductOpsState
    @State private var editingPolicy: ProjectPolicy?

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 48)
        .navigationTitle("方針")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let policy = state.policy {
                    Button {
                        editingPolicy = policy
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("方針を編集")
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
        .sheet(item: $editingPolicy) { policy in
            NavigationStack {
                ProjectPolicyEditSheet(state: state, policy: policy)
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
                message: "おすすめタブのメニューからログインしてください。"
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
                    Label("方針を読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .listRowSeparator(.hidden)
            case .loaded(let policy):
                Section("基本") {
                    PolicyTextRow(title: "目的", text: policy.productGoal)
                    PolicyTextRow(title: "対象", text: policy.targetPersona)
                    PolicyTextRow(title: "提供価値", text: policy.valueProposition)
                    PolicyTextRow(title: "価格仮説", text: policy.pricingHypothesis)
                }

                PolicyArraySection(title: "重視する観点", values: policy.evaluationCriteria)
                PolicyArraySection(title: "やらないこと", values: policy.nonGoals)
                PolicyArraySection(title: "制約", values: policy.constraints)

                Section("更新") {
                    HStack {
                        Text("version")
                        Spacer()
                        Text("\(policy.version)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("updated")
                        Spacer()
                        Text(ActionDateFormat.string(from: policy.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct PolicyTextRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

private struct PolicyArraySection: View {
    let title: String
    let values: [String]

    var body: some View {
        Section(title) {
            if values.isEmpty {
                Text("未設定")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ProjectPolicyEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    @State private var targetPersona: String
    @State private var productGoal: String
    @State private var valueProposition: String
    @State private var pricingHypothesis: String
    @State private var evaluationCriteriaText: String
    @State private var nonGoalsText: String
    @State private var constraintsText: String

    init(state: ProductOpsState, policy: ProjectPolicy) {
        self.state = state
        _targetPersona = State(initialValue: policy.targetPersona)
        _productGoal = State(initialValue: policy.productGoal)
        _valueProposition = State(initialValue: policy.valueProposition)
        _pricingHypothesis = State(initialValue: policy.pricingHypothesis)
        _evaluationCriteriaText = State(initialValue: policy.evaluationCriteria.joined(separator: "\n"))
        _nonGoalsText = State(initialValue: policy.nonGoals.joined(separator: "\n"))
        _constraintsText = State(initialValue: policy.constraints.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("基本") {
                TextField("目的", text: $productGoal, axis: .vertical)
                    .lineLimit(2...4)
                TextField("対象", text: $targetPersona, axis: .vertical)
                    .lineLimit(2...4)
                TextField("提供価値", text: $valueProposition, axis: .vertical)
                    .lineLimit(2...4)
                TextField("価格仮説", text: $pricingHypothesis, axis: .vertical)
                    .lineLimit(2...4)
            }

            multilineSection("重視する観点", text: $evaluationCriteriaText)
            multilineSection("やらないこと", text: $nonGoalsText)
            multilineSection("制約", text: $constraintsText)
        }
        .navigationTitle("方針を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if state.isSavingPolicy {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .disabled(state.isSavingPolicy)
            }
        }
    }

    private func multilineSection(_ title: String, text: Binding<String>) -> some View {
        Section(title) {
            TextEditor(text: text)
                .frame(minHeight: 120)
        }
    }

    private func save() async {
        let fields = ProjectPolicyEditableFields(
            targetPersona: targetPersona.trimmingCharacters(in: .whitespacesAndNewlines),
            productGoal: productGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            valueProposition: valueProposition.trimmingCharacters(in: .whitespacesAndNewlines),
            pricingHypothesis: pricingHypothesis.trimmingCharacters(in: .whitespacesAndNewlines),
            evaluationCriteria: lines(from: evaluationCriteriaText),
            constraints: lines(from: constraintsText),
            nonGoals: lines(from: nonGoalsText)
        )
        if await state.updatePolicy(fields: fields) != nil {
            dismiss()
        }
    }

    private func lines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
