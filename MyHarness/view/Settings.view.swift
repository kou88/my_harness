import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let state: SettingsState

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Push通知") {
                Toggle(
                    "Push通知",
                    isOn: Binding(
                        get: { state.pushPreferences.pushEnabled },
                        set: { value in Task { await state.setPushEnabled(value) } }
                    )
                )
                .disabled(!state.canEditPushPreferences || state.isSavingPush)

                Toggle(
                    "実行完了・失敗",
                    isOn: Binding(
                        get: { state.pushPreferences.missionEventsEnabled },
                        set: { value in Task { await state.setMissionUpdatesEnabled(value) } }
                    )
                )
                .disabled(!state.canEditPushPreferences || !state.pushPreferences.pushEnabled || state.isSavingPush)

                Toggle(
                    "新しいおすすめ",
                    isOn: Binding(
                        get: { state.pushPreferences.recommendationsEnabled },
                        set: { value in Task { await state.setRecommendationsEnabled(value) } }
                    )
                )
                .disabled(!state.canEditPushPreferences || !state.pushPreferences.pushEnabled || state.isSavingPush)

                LabeledContent("通知権限", value: state.pushPermissionState.label)
                LabeledContent("端末登録", value: state.pushRegistrationState.label)

                if state.pushPermissionState == .denied {
                    Button {
                        state.openSystemNotificationSettings()
                    } label: {
                        Label("iOSの通知設定を開く", systemImage: "arrow.up.forward.app")
                    }
                } else if state.canEditPushPreferences,
                          state.pushPreferences.pushEnabled,
                          state.pushPermissionState == .notDetermined || state.pushPermissionState == .unknown {
                    Button {
                        Task { await state.requestPushAuthorization() }
                    } label: {
                        Label("通知を許可", systemImage: "bell.badge")
                    }
                    .disabled(state.isSavingPush)
                }
            }

            Section("今日の通知") {
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
        .onReceive(NotificationCenter.default.publisher(for: .actionPushRegistrationStatusChanged)) { _ in
            Task { await state.refreshPushRegistrationState() }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(state: SettingsState(
            useCases: try! AppDependencies.preview().useCases,
            authSession: nil,
            apiClient: nil
        ))
    }
}
