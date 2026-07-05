import SwiftUI

@MainActor
struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let state: ItemEditorState
    let afterSave: () async -> Void

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                TextField("項目名", text: $state.title)
                    .submitLabel(.done)

                Picker("タイプ", selection: $state.type) {
                    ForEach(RoutineItemType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
            }

            if let error = state.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(state.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(state.isSaving ? "保存中" : "保存") {
                    Task {
                        if await state.save() {
                            await afterSave()
                            dismiss()
                        }
                    }
                }
                .disabled(!state.isValid || state.isSaving)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ItemEditorView(
            state: ItemEditorState(useCases: try! AppDependencies.preview().useCases),
            afterSave: {}
        )
    }
}

