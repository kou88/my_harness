import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let state: SettingsState

    var body: some View {
        @Bindable var state = state

        Form {
            Section("通知") {
                DatePicker("通知時刻", selection: $state.notificationDate, displayedComponents: .hourAndMinute)

                LabeledContent("現在の設定", value: state.scheduleText)
                LabeledContent("通知権限", value: state.permissionText)

                Button {
                    Task { await state.saveNotificationTime(state.notificationDate) }
                } label: {
                    Label("通知を有効化 / 再設定", systemImage: "bell.badge")
                }
                .disabled(state.isSaving)
            }

            Section("ウィジェット") {
                Picker("表示", selection: $state.widgetTextDirection) {
                    ForEach(WidgetTextDirection.allCases) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: state.widgetTextDirection) { _, direction in
                    Task { await state.saveWidgetTextDirection(direction) }
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
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    dismiss()
                }
            }
        }
        .task {
            await state.load()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(state: SettingsState(useCases: try! AppDependencies.preview().useCases))
    }
}
