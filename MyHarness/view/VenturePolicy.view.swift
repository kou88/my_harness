import SwiftUI

@MainActor
struct VenturePolicyView: View {
    let state: ProductOpsState
    @State private var editingPolicy: VenturePolicy?

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
                    Button {
                        editingPolicy = policy
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("事業方針を編集")
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
                VenturePolicyEditSheet(state: state, policy: policy)
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
                    ProductOpsMarkdownView(markdown: policy.bodyMarkdown)
                        .padding(.vertical, 4)
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
}

private struct VenturePolicyEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    @State private var bodyMarkdown: String
    @State private var reason = ""
    private let originalMarkdown: String

    init(state: ProductOpsState, policy: VenturePolicy) {
        self.state = state
        let editableMarkdown = Self.editableMarkdown(from: policy.bodyMarkdown)
        originalMarkdown = Self.normalized(editableMarkdown)
        _bodyMarkdown = State(initialValue: editableMarkdown)
    }

    var body: some View {
        Form {
            Section("Markdown") {
                TextEditor(text: $bodyMarkdown)
                    .font(.body.monospaced())
                    .frame(minHeight: 440)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("事業方針Markdown")
            }

            Section("変更理由") {
                TextField("今回変更する理由", text: $reason, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("事業方針を編集")
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
                .disabled(
                    state.isSavingPolicy
                        || normalizedMarkdown.isEmpty
                        || normalizedReason.isEmpty
                        || !hasChanges
                )
            }
        }
    }

    private var normalizedMarkdown: String {
        Self.normalized(bodyMarkdown)
    }

    private var normalizedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        normalizedMarkdown != originalMarkdown
    }

    private static func editableMarkdown(from markdown: String) -> String {
        let immutableSection = "\n## システム安全制約"
        guard let range = markdown.range(of: immutableSection) else {
            return markdown
        }
        return String(markdown[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        if await state.updatePolicy(bodyMarkdown: normalizedMarkdown, reason: normalizedReason) != nil {
            dismiss()
        }
    }
}
