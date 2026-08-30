import SwiftUI

struct AIChatComposer: View {
    @Bindable var state: AIChatState
    let conversationId: String?
    let onModels: () -> Void
    let onSettings: () -> Void
    let onSent: (String) -> Void
    @FocusState private var focused: Bool
    private var modelLocked: Bool { state.activeRun != nil || state.hasPendingSubmission || state.isSending }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(conversationId == nil ? "今日はどのようにお手伝いしましょうか？" : "メッセージを送信", text: $state.composerText, axis: .vertical)
                .font(.system(size: 16)).lineLimit(1...8).textFieldStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 4)
                .focused($focused).disabled(state.hasPendingSubmission)
                .accessibilityIdentifier("AI.prompt")
            HStack(spacing: 6) {
                Menu {
                    Button("モデル設定", systemImage: "slider.horizontal.3", action: onSettings).disabled(state.selectedModel == nil || modelLocked)
                    Button("コードを実行", systemImage: "terminal") { state.composerText += "execute_codeを使ってPythonで"; focused = true }
                    Button("Webを調べる", systemImage: "globe") { state.composerText += "Webで調べて、出典とともに教えてください。"; focused = true }
                } label: { Image(systemName: "plus").font(.system(size: 19, weight: .light)).frame(width: 36, height: 36) }
                    .accessibilityLabel("もっと見る").disabled(state.hasPendingSubmission)
                if let model = state.selectedModel, let settings = state.settings {
                    Menu {
                        Text("Reasoning effort")
                        ForEach(model.reasoningEfforts, id: \.self) { effort in
                            if let budget = model.reasoningBudgets[effort] {
                                let candidate = AISettings(contextLength: settings.contextLength,
                                    maxOutputTokens: max(settings.maxOutputTokens, budget + 256), reasoningEffort: effort)
                                Button { state.saveSettings(candidate) } label: {
                                    Label(effort + (candidate.maxOutputTokens > settings.maxOutputTokens
                                        ? " · 出力上限 \(candidate.maxOutputTokens.formatted())へ変更" : ""),
                                        systemImage: effort == settings.reasoningEffort ? "checkmark" : "circle")
                                }.disabled(!model.accepts(candidate))
                            } else {
                                Text(effort + " · モデル設定が不正です")
                            }
                        }
                        Divider()
                        Button("モデル設定", systemImage: "slider.horizontal.3", action: onSettings)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "brain").font(.system(size: 13))
                            Text(settings.reasoningEffort).font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }.fixedSize().frame(height: 36)
                    }.disabled(modelLocked).accessibilityLabel("Reasoning effort: " + settings.reasoningEffort)
                        .accessibilityIdentifier("AI.reasoningEffort")
                }
                Spacer(minLength: 0)
                Button(action: onModels) {
                    HStack(spacing: 8) {
                        Text(state.selectedModel?.name ?? "モデルを選択").font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                        Image(systemName: state.sharedMode ? "lock.fill" : "chevron.down").font(.system(size: 9))
                    }.frame(maxWidth: 180).frame(height: 36)
                }.disabled(modelLocked || state.sharedMode).accessibilityLabel((state.sharedMode ? "共有モデル: " : "モデルを選択: ") + (state.selectedModel?.name ?? "未選択"))
                    .accessibilityIdentifier("AI.modelMenu")
                if let run = state.activeRun {
                    Button { Task { await state.cancel() } } label: {
                        Image(systemName: "stop.fill").font(.system(size: 13)).foregroundStyle(AIChatStyle.onAction)
                            .frame(width: 32, height: 32).background(AIChatStyle.action, in: Circle())
                    }.disabled(run.cancelRequested).accessibilityLabel("実行を停止")
                } else {
                    Button {
                        focused = false
                        Task { if let id = await state.send(conversationId: conversationId) { onSent(id) } }
                    } label: {
                        Group {
                            if state.isSending { ProgressView().tint(AIChatStyle.onAction) }
                            else { Image(systemName: state.hasPendingSubmission ? "arrow.clockwise" : "arrow.up").font(.system(size: 18, weight: .semibold)) }
                        }.foregroundStyle(AIChatStyle.onAction).frame(width: 32, height: 32)
                            .background(state.canSend || state.isSending ? AIChatStyle.action : AIChatStyle.disabledAction, in: Circle())
                    }.disabled(!state.canSend).accessibilityLabel(state.hasPendingSubmission ? "同じ依頼を再送" : "送信")
                        .accessibilityIdentifier("AI.send")
                }
            }.buttonStyle(.plain).padding(.horizontal, 8).padding(.bottom, 7)
            if state.hasPendingSubmission {
                Text("送信結果が未確認です。同じ依頼を再送できます。")
                    .font(.caption).foregroundStyle(AIChatStyle.muted).padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .background(AIChatStyle.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(focused ? AIChatStyle.focusedBorder : AIChatStyle.border, lineWidth: 1))
    }
}

struct AIModelPicker: View {
    @Bindable var state: AIChatState
    let onClose: () -> Void
    @State private var query = ""
    private var models: [AIModel] { query.isEmpty ? state.models : state.models.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(AIChatStyle.muted)
                TextField("モデルを検索", text: $query).textFieldStyle(.plain).font(.system(size: 15)).autocorrectionDisabled()
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 32, height: 36) }.accessibilityLabel("モデル選択を閉じる")
            }.padding(.horizontal, 14).padding(.vertical, 6)
            Divider().overlay(AIChatStyle.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text("モデルを選択").font(.system(size: 12, weight: .medium)).foregroundStyle(AIChatStyle.muted).padding(.horizontal, 12).padding(.vertical, 8)
                    ForEach(models) { model in
                        Button {
                            guard !state.sharedMode, state.activeRun == nil, !state.hasPendingSubmission else { return }
                            state.choose(model); onClose()
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "cpu").font(.system(size: 18)).foregroundStyle(AIChatStyle.muted)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.name).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 5) {
                                        Circle().fill(model.online ? Color.green : Color.gray).frame(width: 5, height: 5)
                                        Text(model.online ? model.hostName : "オフライン").font(.system(size: 11)).foregroundStyle(AIChatStyle.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                                if model.id == state.selectedModel?.id { Image(systemName: "checkmark").font(.system(size: 13)) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.id == state.selectedModel?.id ? AIChatStyle.bubble : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(!model.online)
                    }
                    if models.isEmpty { Text(state.isLoading ? "読み込み中" : "該当するモデルがありません").font(.callout).foregroundStyle(AIChatStyle.muted).padding(12) }
                }.padding(6)
            }
        }.background(AIChatStyle.sidebar, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AIChatStyle.border))
            .shadow(color: .black.opacity(0.3), radius: 20)
            .accessibilityAddTraits(.isModal)
    }
}

struct AIChatSidebar: View {
    @Environment(AppRouter.self) private var router
    @Bindable var state: AIChatState
    let selectedId: String?
    let onClose: () -> Void
    let onNew: () -> Void
    let onOpen: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MyHarness").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "sidebar.left").frame(width: 44, height: 44) }.accessibilityLabel("サイドバーを閉じる")
            }.padding(.leading, 20).padding(.trailing, 6)
            Button(action: onNew) {
                Label("新しいチャット", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 44).contentShape(Rectangle())
            }.buttonStyle(AIChatRowButtonStyle())
                .padding(.horizontal, 20)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("検索", text: $state.searchText).textFieldStyle(.plain).autocorrectionDisabled()
                if !state.searchText.isEmpty { Button { state.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AIChatStyle.muted) }.accessibilityLabel("検索をクリア") }
            }.frame(height: 44).padding(.horizontal, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("チャット").font(.system(size: 12, weight: .semibold)).foregroundStyle(AIChatStyle.muted).padding(.horizontal, 12).padding(.top, 26).padding(.bottom, 10)
                    if state.isLoading && state.conversations.isEmpty { ProgressView().padding() }
                    ForEach(state.filteredConversations) { conversation in
                        HStack(spacing: 0) {
                            Button { onOpen(conversation.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conversation.title).lineLimit(1).font(.system(size: 14))
                                    let activity = state.activity(conversation.id)
                                    if !activity.isEmpty {
                                        Text(activity).font(.system(size: 11)).foregroundStyle(AIChatStyle.muted)
                                    }
                                }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }.buttonStyle(AIChatRowButtonStyle())
                                .accessibilityIdentifier("AI.conversation." + conversation.id)
                            Menu {
                                Button("会話を削除", systemImage: "trash", role: .destructive) { onDelete(conversation.id) }
                                    .disabled(!state.canDelete(conversation.id))
                            } label: { Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .accessibilityLabel(conversation.title + "の操作")
                        }
                        .background(selectedId == conversation.id ? AIChatStyle.bubble : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if !state.isLoading && state.filteredConversations.isEmpty {
                        Text(state.searchText.isEmpty ? "会話はまだありません" : "該当する会話がありません").font(.caption).foregroundStyle(AIChatStyle.muted).padding(12)
                    }
                }.padding(.horizontal, 8)
            }.refreshable { await state.loadList() }.scrollDismissesKeyboard(.interactively)
            Menu {
                Button("今日", systemImage: "checklist") { leave(.today) }
                Button("次にやる", systemImage: "sparkles") { leave(.nextActions) }
                Button("記事", systemImage: "doc.richtext") { leave(.articles) }
                Button("テレビ", systemImage: "tv") { leave(.television) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 28))
                    Text("MyHarness").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 16))
                }.padding(16).frame(maxWidth: .infinity)
            }.accessibilityLabel("MyHarnessの他の機能")
        }
        .font(.system(size: 15)).buttonStyle(.plain)
        .background(AIChatStyle.sidebar.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }

    private func leave(_ tab: AppTab) { onClose(); router.selectedTab = tab }
}

private struct AIChatRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AIChatStyle.pressed : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}
