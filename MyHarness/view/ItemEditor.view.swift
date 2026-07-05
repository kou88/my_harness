import SwiftUI

@MainActor
struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let state: ItemEditorState
    let afterSave: () async -> Void
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                TextField("項目名", text: $state.title)
                    .submitLabel(.done)
            }

            Section("繰り返し") {
                Picker("繰り返し", selection: $state.repeatPreset) {
                    ForEach(RoutineRepeatPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if state.repeatPreset == .custom {
                    WeekdaySelectionView(
                        selectedWeekdays: $state.customRepeatWeekdays,
                        onToggle: state.toggleWeekday
                    )
                }
            }

            if state.isSaving {
                Section {
                    Label("保存中", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Task {
                        await saveImmediately()
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: state.title) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: state.repeatPreset) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: state.customRepeatWeekdays) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            autosaveTask = nil
        }
    }

    @MainActor
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await saveImmediately()
        }
    }

    @MainActor
    private func saveImmediately() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        if await state.autosaveIfNeeded() {
            await afterSave()
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
                            selectedWeekdays.contains(weekday) ? Color.green : Color(.secondarySystemGroupedBackground),
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
