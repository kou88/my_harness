import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AIConversationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let id: String
    let state: AIChatState

    @State private var isShowingFileImporter = false
    @State private var isShowingRename = false
    @State private var isShowingDeleteConfirmation = false
    @State private var renameText = ""
    @State private var editingMessage: AIMessage?
    @State private var editedText = ""
    @State private var autoFollow = true

    var body: some View {
        Group {
            if state.isLoadingDetail && state.detail == nil {
                ProgressView("会話を読み込み中")
            } else if let detail = state.detail {
                conversation(detail)
            } else {
                ContentUnavailableView(
                    "会話を表示できません",
                    systemImage: "exclamationmark.bubble",
                    description: Text(state.errorMessage ?? "会話が見つかりません。")
                )
            }
        }
        .navigationTitle(state.detail?.conversation.title ?? "AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .task(id: id) { await state.openConversation(id: id) }
        .onDisappear { state.closeConversation() }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleImportedFiles
        )
        .alert("会話タイトルを変更", isPresented: $isShowingRename) {
            TextField("タイトル", text: $renameText)
            Button("変更") { Task { await state.renameConversation(title: renameText) } }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("メッセージを編集して分岐", isPresented: editBinding) {
            TextField("メッセージ", text: $editedText, axis: .vertical)
            Button("分岐して送信") {
                guard let message = editingMessage else { return }
                Task { await state.editAndBranch(messageId: message.id, text: editedText) }
                editingMessage = nil
            }
            Button("キャンセル", role: .cancel) { editingMessage = nil }
        } message: {
            Text("元の会話は残したまま、編集地点から新しい分岐を作ります。")
        }
        .confirmationDialog("この会話を削除しますか？", isPresented: $isShowingDeleteConfirmation) {
            Button("削除", role: .destructive) {
                Task {
                    if await state.deleteConversation(id: id) { dismiss() }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("会話履歴、実行イベント、承認履歴を削除します。")
        }
        .alert(
            "AI",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "エラーが発生しました。")
        }
    }

    @ViewBuilder
    private func conversation(_ detail: AIConversationDetail) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    AIConversationContextBar(conversation: detail.conversation)

                    ForEach(detail.messages) { message in
                        AIMessageView(
                            message: message,
                            onCopy: { UIPasteboard.general.string = message.text },
                            onEdit: message.role == .user ? {
                                editingMessage = message
                                editedText = message.text
                            } : nil,
                            onRegenerate: message.role == .assistant ? {
                                Task<Void, Never> { await state.regenerate(messageId: message.id) }
                            } : nil
                        )
                    }

                    if !state.liveAssistantText.isEmpty {
                        AILiveAssistantView(text: state.liveAssistantText)
                    }

                    if !detail.events.isEmpty {
                        AIRunTimeline(events: detail.events)
                    }

                    ForEach(state.activeApprovals) { approval in
                        AIApprovalCard(approval: approval) { decision in
                            Task { await state.decideApproval(id: approval.id, decision: decision) }
                        }
                    }

                    if let run = detail.run, let error = run.errorMessage, !error.isEmpty {
                        AIErrorCard(message: error) {
                            if let message = detail.messages.last(where: { $0.role == .assistant }) {
                                Task<Void, Never> { await state.regenerate(messageId: message.id) }
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("conversation-bottom")
                        .onAppear { autoFollow = true }
                        .onDisappear { autoFollow = false }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .simultaneousGesture(
                DragGesture().onChanged { value in
                    if value.translation.height > 10 { autoFollow = false }
                }
            )
            .onChange(of: state.liveAssistantText) { _, _ in
                guard autoFollow else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: detail.messages.count) { _, _ in
                guard autoFollow else { return }
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !autoFollow {
                    Button {
                        autoFollow = true
                        withAnimation { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.callout.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .accessibilityLabel("最新メッセージへ移動")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AIComposerView(
                text: Bindable(state).composerText,
                attachments: state.uploadedAttachments,
                isUploading: state.isUploading,
                isSending: state.isSending,
                isRunActive: detail.run?.status.isTerminal == false,
                onAttach: { isShowingFileImporter = true },
                onRemoveAttachment: { attachment in
                    Task { await state.removeUploadedAttachment(id: attachment.id) }
                },
                onSend: { Task { await state.send() } },
                onStop: { Task { await state.stop() } }
            )
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if let conversation = state.detail?.conversation {
            ToolbarItem(placement: .principal) {
                Menu {
                    let available = state.models.filter {
                        $0.hostId == conversation.hostId && $0.isAvailable
                    }
                    ForEach(available) { model in
                        Menu(model.displayName) {
                            ForEach(model.reasoningEfforts, id: \.self) { effort in
                                Button {
                                    Task { await state.updateModel(model: model, effort: effort) }
                                } label: {
                                    if model.model == conversation.model && effort == conversation.reasoningEffort {
                                        Label("推論: \(effort.label)", systemImage: "checkmark")
                                    } else {
                                        Text("推論: \(effort.label)")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text(conversation.title).font(.headline).lineLimit(1)
                        Text("\(conversation.model) · 推論\(conversation.reasoningEffort.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = conversation.title
                        isShowingRename = true
                    } label: {
                        Label("タイトルを変更", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("会話を削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("会話メニュー")
            }
        }
    }

    private var editBinding: Binding<Bool> {
        Binding(
            get: { editingMessage != nil },
            set: { if !$0 { editingMessage = nil } }
        )
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            state.errorMessage = error.localizedDescription
        case .success(let urls):
            Task {
                for url in urls {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
                        await state.upload(
                            data: data,
                            fileName: url.lastPathComponent,
                            mimeType: type?.preferredMIMEType ?? "application/octet-stream"
                        )
                    } catch {
                        state.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct AIConversationContextBar: View {
    let conversation: AIConversationSummary

    var body: some View {
        HStack(spacing: 8) {
            Label(conversation.provider.label, systemImage: conversation.provider == .openai ? "sparkles" : "point.3.connected.trianglepath.dotted")
            Divider().frame(height: 14)
            Label(conversation.mode.label, systemImage: conversation.mode.systemImage)
            Divider().frame(height: 14)
            Label(URL(fileURLWithPath: conversation.workspacePath).lastPathComponent, systemImage: "folder")
                .lineLimit(1)
            Spacer(minLength: 0)
            AIStatusLabel(status: conversation.latestRunStatus)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

private struct AIMessageView: View {
    let message: AIMessage
    let onCopy: () -> Void
    let onEdit: (() -> Void)?
    let onRegenerate: (() -> Void)?

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 42)
                AIMessageBody(text: message.text, isUser: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                    .contextMenu {
                        Button(action: onCopy) { Label("コピー", systemImage: "doc.on.doc") }
                        if let onEdit {
                            Button(action: onEdit) { Label("編集して分岐", systemImage: "arrow.triangle.branch") }
                        }
                    }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                AIMessageBody(text: message.text, isUser: false)
                HStack(spacing: 12) {
                    Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("回答をコピー")
                    if let onRegenerate {
                        Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("回答を再生成")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AIMessageBody: View {
    let text: String
    let isUser: Bool

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let content):
                    Text(markdown: content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let content):
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(language.isEmpty ? "code" : language)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = content
                            } label: {
                                Label("コピー", systemImage: "doc.on.doc")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        ScrollView(.horizontal) {
                            Text(content)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                        }
                    }
                    .background(Color.secondary.opacity(isUser ? 0.08 : 0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct AILiveAssistantView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIMessageBody(text: text, isUser: false)
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("生成中")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIRunTimeline: View {
    let events: [AIEvent]

    private var visibleEvents: [AIEvent] {
        events.filter {
            switch $0.type {
            case .reasoningStarted, .reasoningDelta, .reasoningCompleted,
                 .toolCallStarted, .toolCallUpdated, .toolCallCompleted,
                 .fileChangeCreated, .commandStarted, .commandOutput, .commandCompleted,
                 .usageUpdated, .runFailed:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        if !visibleEvents.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleEvents) { event in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: icon(for: event.type))
                                .foregroundStyle(color(for: event.type))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label(for: event.type)).font(.caption.weight(.semibold))
                                if !event.displayText.isEmpty {
                                    Text(event.displayText)
                                        .font(event.type == .commandOutput ? .system(.caption, design: .monospaced) : .caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("実行内容", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func icon(for type: AIEventType) -> String {
        switch type {
        case .reasoningStarted, .reasoningDelta, .reasoningCompleted: return "brain"
        case .commandStarted, .commandOutput, .commandCompleted: return "terminal"
        case .fileChangeCreated: return "doc.badge.gearshape"
        case .toolCallStarted, .toolCallUpdated, .toolCallCompleted: return "wrench.and.screwdriver"
        case .usageUpdated: return "gauge.with.dots.needle.33percent"
        case .runFailed: return "exclamationmark.triangle"
        default: return "circle"
        }
    }

    private func color(for type: AIEventType) -> Color {
        type == .runFailed ? .red : .secondary
    }

    private func label(for type: AIEventType) -> String {
        switch type {
        case .reasoningStarted: return "実行計画"
        case .reasoningDelta: return "計画を更新"
        case .reasoningCompleted: return "計画を確定"
        case .commandStarted: return "コマンドを開始"
        case .commandOutput: return "コマンド出力"
        case .commandCompleted: return "コマンド完了・テスト結果"
        case .fileChangeCreated: return "ファイル差分"
        case .toolCallStarted: return "Tool / MCP呼び出し"
        case .toolCallUpdated: return "Tool / MCP更新"
        case .toolCallCompleted: return "Tool / MCP完了"
        case .usageUpdated: return "使用トークン"
        case .runFailed: return "実行失敗"
        default: return type.rawValue
        }
    }
}

private struct AIApprovalCard: View {
    let approval: AIApproval
    let onDecision: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("承認が必要です", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(approval.title).font(.subheadline.weight(.semibold))
            Text(approval.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("拒否", role: .destructive) { onDecision("decline") }
                    .buttonStyle(.bordered)
                Spacer()
                if approval.allowForSession {
                    Button("会話中は許可") { onDecision("accept_for_session") }
                        .buttonStyle(.bordered)
                }
                Button("今回だけ許可") { onDecision("accept_once") }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.28)))
    }
}

private struct AIErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("実行に失敗しました", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.headline)
            Text(message).font(.caption).textSelection(.enabled)
            Button("再試行", action: onRetry).buttonStyle(.bordered)
        }
        .padding(14)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AIComposerView: View {
    @Binding var text: String
    let attachments: [AIAttachment]
    let isUploading: Bool
    let isSending: Bool
    let isRunActive: Bool
    let onAttach: () -> Void
    let onRemoveAttachment: (AIAttachment) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachment.contentType.hasPrefix("image/") ? "photo" : "doc")
                                Text(attachment.fileName).lineLimit(1)
                                Button { onRemoveAttachment(attachment) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    if isUploading { ProgressView().controlSize(.small) } else { Image(systemName: "plus") }
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .accessibilityLabel("ファイルを添付")

                TextField("メッセージ", text: $text, axis: .vertical)
                    .lineLimit(1...6)

                Button(action: isRunActive ? onStop : onSend) {
                    Image(systemName: isRunActive ? "stop.fill" : "arrow.up")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(isRunActive ? Color.primary : Color.accentColor, in: Circle())
                }
                .disabled((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty && !isRunActive) || isSending)
                .accessibilityLabel(isRunActive ? "生成を停止" : "送信")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.24)))
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background(.bar)
    }
}

private enum MarkdownBlock {
    case markdown(String)
    case code(language: String, content: String)

    static func parse(_ text: String) -> [MarkdownBlock] {
        let pieces = text.components(separatedBy: "```")
        return pieces.enumerated().compactMap { index, piece in
            guard !piece.isEmpty else { return nil }
            if index.isMultiple(of: 2) { return .markdown(piece) }
            let lines = piece.split(separator: "\n", omittingEmptySubsequences: false)
            let language = lines.first.map(String.init) ?? ""
            let content = lines.dropFirst().map(String.init).joined(separator: "\n")
            return .code(language: language, content: content)
        }
    }
}

private extension Text {
    init(markdown: String) {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            self.init(attributed)
        } else {
            self.init(markdown)
        }
    }
}
