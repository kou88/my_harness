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
                Section {
                    PolicyMarkdownBody(markdown: policy.bodyMarkdown)
                }

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

private struct PolicyMarkdownBody: View {
    let markdown: String

    var body: some View {
        Text(renderedMarkdown)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

private struct ProjectPolicyEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ProductOpsState
    @State private var bodyMarkdown: String

    init(state: ProductOpsState, policy: ProjectPolicy) {
        self.state = state
        _bodyMarkdown = State(initialValue: policy.bodyMarkdown)
    }

    var body: some View {
        Form {
            Section("Markdown") {
                TextEditor(text: $bodyMarkdown)
                    .font(.body.monospaced())
                    .frame(minHeight: 460)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
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
                .disabled(state.isSavingPolicy || bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() async {
        let fields = ProjectPolicyEditableFields(
            bodyMarkdown: bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if await state.updatePolicy(fields: fields) != nil {
            dismiss()
        }
    }
}
