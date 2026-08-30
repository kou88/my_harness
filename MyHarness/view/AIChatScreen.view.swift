import SwiftUI
import UIKit

// Open WebUI's narrow layout: one canvas, an overlay drawer and a two-row composer.
enum AIChatStyle {
    // Resolve against the app's appearance, including changes while a chat is open.
    static let canvas = adaptive(light: 1, dark: 0.09)
    static let surface = adaptive(light: 1, dark: 0.12)
    static let sidebar = adaptive(light: 0.975, dark: 0.125)
    static let bubble = adaptive(light: 0.945, dark: 0.16)
    static let pressed = adaptive(light: 0.87, dark: 0.28)
    static let muted = adaptive(light: 0.42, dark: 0.65)
    static let border = adaptive(light: 0.87, dark: 0.22)
    static let focusedBorder = adaptive(light: 0.65, dark: 0.3)
    static let controls = adaptive(light: 0.33, dark: 0.8)
    static let action = adaptive(light: 0.08, dark: 1)
    static let onAction = adaptive(light: 1, dark: 0)
    static let disabledAction = adaptive(light: 0.82, dark: 0.42)
    static let code = adaptive(light: 0.975, dark: 0.125)

    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }
}

struct AIChatScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: AIChatState
    let conversationId: String?
    @State private var showSidebar = false
    @State private var showModels = false
    @State private var showSettings = false
    @State private var showSharing = false
    @State private var deleteTarget: String?
    @State private var showRename = false
    @State private var title = ""

    private var isNew: Bool { conversationId == nil }
    private var modelLocked: Bool { state.sharedMode || state.activeRun != nil || state.hasPendingSubmission }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                AIChatStyle.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if !state.isSignedIn { signIn }
                    else if isNew { welcome }
                    else if let detail = state.detail, detail.id == conversationId {
                        if detail.runs.isEmpty {
                            VStack(spacing: 12) {
                                if state.isSending { ProgressView("送信内容を確認中") }
                                else if state.hasPendingSubmission { Text("送信結果を確認できません。入力欄から再送してください。") }
                                else if state.isLoading { ProgressView("読み込み中") }
                                else { Text("メッセージを送信して会話を始めましょう") }
                            }.font(.callout).foregroundStyle(AIChatStyle.muted)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            AIMessageList(detail: detail, state: state).id(detail.id)
                        }
                    } else {
                        VStack(spacing: 12) {
                            if state.isLoading { ProgressView("読み込み中") }
                            else {
                                Text("会話を読み込めません")
                                Button("再読み込み") { Task { if let conversationId { await state.openConversation(id: conversationId) } } }
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if !isNew {
                        notices
                        composer.padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 8)
                    }
                }
                .accessibilityHidden(showSidebar || showModels)
                if showSidebar {
                    Color.black.opacity(0.48).ignoresSafeArea()
                        .onTapGesture { toggleSidebar(false) }.accessibilityHidden(true)
                    AIChatSidebar(state: state, selectedId: conversationId, onClose: { toggleSidebar(false) }, onNew: newChat, onOpen: openConversation, onDelete: { deleteTarget = $0 })
                        .frame(width: min(300, geometry.size.width - 48))
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
                if showModels {
                    Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { showModels = false }.accessibilityHidden(true)
                    AIModelPicker(state: state, onClose: { showModels = false })
                        .frame(maxWidth: 440, maxHeight: min(geometry.size.height - 48, 540))
                        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity).zIndex(2)
                }
            }
            .clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard !showModels, !showSettings, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if showSidebar && value.translation.width < -60 { toggleSidebar(false) }
                else if !showSidebar && value.startLocation.x <= 32 && value.translation.width > 60 {
                    toggleSidebar(true)
                    Task { await state.loadList() }
                }
            })
        }
        .background(AIChatStyle.canvas.ignoresSafeArea())
        .foregroundStyle(.primary)
        .tint(.primary)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .navigationBarBackButtonHidden()
        .task(id: conversationId) {
            if state.models.isEmpty || isNew { await state.loadList() }
            guard !Task.isCancelled else { return }
            if let conversationId { await state.openConversation(id: conversationId) }
            else { state.newChat() }
        }
        .sheet(isPresented: $showSettings) {
            if let model = state.selectedModel, let settings = state.settings {
                AISettingsView(model: model, draft: settings, sharedMode: state.sharedMode) { state.saveSettings($0) }
            }
        }
        .sheet(isPresented: $showSharing) {
            if let sharing = state.sharing { AISharingView(state: state, draft: sharing) }
        }
        .alert("会話を削除しますか？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { id in
            Button("削除", role: .destructive) {
                Task { if await state.delete(id), id == conversationId { newChat() } }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in Text("会話履歴と実行イベントを削除します。Hermesのmemoryと作成したファイルは残ります。") }
        .alert("会話の名前", isPresented: $showRename) {
            TextField("名前", text: $title)
            Button("保存") { Task { await state.rename(title) } }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { toggleSidebar(true); Task { await state.loadList() } } label: {
                Image(systemName: "sidebar.left").font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44)
            }.accessibilityLabel("サイドバーを開く").accessibilityIdentifier("AI.sidebar")
            if !isNew {
                Menu {
                    Button("名前を変更", systemImage: "pencil") { title = state.detail?.title ?? ""; showRename = true }
                    Button("会話を削除", systemImage: "trash", role: .destructive) { deleteTarget = conversationId }.disabled(state.activeRun != nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(state.detail?.id == conversationId ? state.detail!.title : "チャット").font(.system(size: 15)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 44)
                }.accessibilityLabel("会話の操作")
                Button(action: newChat) {
                    Image(systemName: "square.and.pencil").font(.system(size: 18)).frame(width: 36, height: 44)
                }.accessibilityLabel("新しいチャット")
            } else { Spacer() }
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18)).frame(width: 44, height: 44)
            }.accessibilityLabel("モデル設定").accessibilityIdentifier("AI.settings")
                .disabled(state.selectedModel == nil || state.activeRun != nil || state.hasPendingSubmission)
        }
        .buttonStyle(.plain).foregroundStyle(AIChatStyle.controls).padding(.horizontal, 2)
        .background(AIChatStyle.canvas)
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AIChatStyle.onAction).frame(width: 34, height: 34).background(AIChatStyle.action, in: RoundedRectangle(cornerRadius: 10))
                        Text(state.selectedModel?.name ?? "モデルを選択")
                            .font(.system(size: 24, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    }.padding(.horizontal, 16).padding(.bottom, 14)
                        .onTapGesture { if !modelLocked { showModels = true } }
                    Text("Hermes Agent / ローカル推論。\n調べる、コードを書く、ファイルを扱う。")
                        .font(.system(size: 14)).foregroundStyle(AIChatStyle.muted)
                        .multilineTextAlignment(.center).lineSpacing(3).padding(.bottom, 22)
                    composer
                    Button { showSharing = true } label: {
                        HStack(spacing: 7) {
                            Image(systemName: state.sharedMode ? "lock.fill" : "square.stack.3d.up")
                            Text("共有モード")
                            Text(state.sharedMode ? "ON · 2件並列" : "OFF").foregroundStyle(AIChatStyle.muted)
                            Image(systemName: "chevron.right").font(.caption2)
                        }.font(.system(size: 13)).padding(.vertical, 14).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(state.sharing == nil).accessibilityIdentifier("AI.sharing")
                    notices.padding(.top, 12)
                    Text("MyHarness · Hermes Agent").font(.system(size: 12)).foregroundStyle(AIChatStyle.muted).padding(.top, 26)
                }
                .padding(.horizontal, 12).padding(.bottom, 90)
                .frame(minHeight: geometry.size.height)
            }.scrollDismissesKeyboard(.interactively)
        }
    }

    private var signIn: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles").font(.system(size: 32))
            Text("今日はどのように\nお手伝いしましょうか？").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Button("ログイン") { Task { await state.signIn() } }.buttonStyle(.borderedProminent).tint(AIChatStyle.action).foregroundStyle(AIChatStyle.onAction)
            notices
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composer: some View {
        AIChatComposer(state: state, conversationId: conversationId, onModels: { showModels = true }, onSettings: { showSettings = true }) { id in
            if isNew { router.aiPath = [.aiConversation(id: id)] }
        }
    }

    private var notices: some View {
        VStack(spacing: 6) {
            if !state.connectionMessage.isEmpty { Text(state.connectionMessage).foregroundStyle(AIChatStyle.muted) }
            if !state.errorMessage.isEmpty { Text(state.errorMessage).foregroundStyle(.red).textSelection(.enabled) }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
    }

    private func toggleSidebar(_ value: Bool) {
        // End the composer's editing/selection before the drawer receives taps.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showSidebar = value }
    }
    private func newChat() {
        toggleSidebar(false); state.newChat(); router.aiPath = []
    }
    private func openConversation(_ id: String) {
        toggleSidebar(false)
        if id != conversationId { router.aiPath = [.aiConversation(id: id)] }
    }
}
