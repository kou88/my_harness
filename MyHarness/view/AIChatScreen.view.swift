import SwiftUI

// Open WebUI's narrow layout: one canvas, an overlay drawer and a two-row composer.
enum AIChatStyle {
    static let canvas = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let sidebar = Color(red: 0.125, green: 0.125, blue: 0.125)
    static let bubble = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let muted = Color(white: 0.65)
    static let border = Color(white: 0.22)
}

struct AIChatScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: AIChatState
    let conversationId: String?
    @State private var showSidebar = false
    @State private var showModels = false
    @State private var showSettings = false
    @State private var showDelete = false
    @State private var showRename = false
    @State private var title = ""

    private var isNew: Bool { conversationId == nil }
    private var modelLocked: Bool { state.activeRun != nil || state.hasPendingSubmission }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                AIChatStyle.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if !state.isSignedIn { signIn }
                    else if isNew { welcome }
                    else if let detail = state.detail, detail.id == conversationId {
                        AIMessageList(detail: detail, state: state)
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
                    AIChatSidebar(state: state, selectedId: conversationId, onClose: { toggleSidebar(false) }, onNew: newChat, onOpen: openConversation)
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
        }
        .background(AIChatStyle.canvas.ignoresSafeArea())
        .foregroundStyle(.white)
        .tint(.white)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .navigationBarBackButtonHidden()
        .task(id: conversationId) {
            if state.models.isEmpty || isNew { await state.loadList() }
            guard !Task.isCancelled else { return }
            if let conversationId { await state.openConversation(id: conversationId) }
            else { state.closeConversation(); state.detail = nil }
        }
        .sheet(isPresented: $showSettings) {
            if let model = state.selectedModel, let settings = state.settings {
                AISettingsView(model: model, draft: settings) { state.saveSettings($0) }.preferredColorScheme(.dark)
            }
        }
        .alert("会話を削除しますか？", isPresented: $showDelete) {
            Button("削除", role: .destructive) {
                Task { if let conversationId, await state.delete(conversationId) { newChat() } }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("会話履歴と実行イベントを削除します。Hermesのmemoryと作成したファイルは残ります。") }
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
                    Button("会話を削除", systemImage: "trash", role: .destructive) { showDelete = true }.disabled(state.activeRun != nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(state.detail?.id == conversationId ? state.detail!.title : "チャット").font(.system(size: 15)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 44)
                }.accessibilityLabel("会話の操作")
                Button(action: newChat) {
                    Image(systemName: "square.and.pencil").font(.system(size: 18)).frame(width: 36, height: 44)
                }.accessibilityLabel("新しいチャット").disabled(state.isSending || state.hasPendingSubmission)
            } else { Spacer() }
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18)).frame(width: 44, height: 44)
            }.accessibilityLabel("モデル設定").accessibilityIdentifier("AI.settings")
                .disabled(state.selectedModel == nil || modelLocked)
        }
        .buttonStyle(.plain).foregroundStyle(Color(white: 0.8)).padding(.horizontal, 2)
        .background(AIChatStyle.canvas)
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.black).frame(width: 34, height: 34).background(.white, in: RoundedRectangle(cornerRadius: 10))
                        Text(state.selectedModel?.name ?? "モデルを選択")
                            .font(.system(size: 24, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    }.padding(.horizontal, 16).padding(.bottom, 14)
                        .onTapGesture { if !modelLocked { showModels = true } }
                    Text("Hermes Agent / ローカル推論。\n調べる、コードを書く、ファイルを扱う。")
                        .font(.system(size: 14)).foregroundStyle(AIChatStyle.muted)
                        .multilineTextAlignment(.center).lineSpacing(3).padding(.bottom, 22)
                    composer
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
            Button("ログイン") { Task { await state.signIn() } }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showSidebar = value }
    }
    private func newChat() {
        guard !state.isSending, !state.hasPendingSubmission else { return }
        toggleSidebar(false); state.newChat(); router.aiPath = []
    }
    private func openConversation(_ id: String) {
        guard !state.isSending, !state.hasPendingSubmission else { return }
        toggleSidebar(false)
        if id != conversationId { state.composerText = ""; router.aiPath = [.aiConversation(id: id)] }
    }
}
