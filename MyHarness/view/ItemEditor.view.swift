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
            }

            Section("繰り返し") {
                WeekdaySelectionView(
                    selectedWeekdays: $state.repeatWeekdays,
                    onToggle: state.toggleWeekday
                )
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

private struct WeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<RoutineWeekday>
    let onToggle: (RoutineWeekday) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RoutineWeekday.allCases) { weekday in
                Button {
                    onToggle(weekday)
                } label: {
                    Text(weekday.shortLabel)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(selectedWeekdays.contains(weekday) ? .white : .primary)
                        .background(
                            selectedWeekdays.contains(weekday) ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(weekday.shortLabel)曜日")
                .accessibilityAddTraits(selectedWeekdays.contains(weekday) ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
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
