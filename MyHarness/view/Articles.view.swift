import Foundation
import SwiftUI

@MainActor
struct ArticleListView: View {
    let state: BlogPostState

    @State private var query = ""
    @State private var presentedSheet: ArticleListSheet?

    var body: some View {
        Group {
            switch state.listState {
            case .idle, .loading:
                ProgressView("記事を読み込んでいます")
            case .failed(let message):
                ContentUnavailableView {
                    Label("記事を読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("再試行") {
                        Task { await state.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loaded:
                articleList
            }
        }
        .navigationTitle("記事")
        .searchable(text: $query, prompt: "タイトル・著者・本文を検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    state.resetImportRequest()
                    presentedSheet = .importRequest
                } label: {
                    Label("記事を追加", systemImage: "plus")
                }
                .accessibilityIdentifier("article-import-open")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .importRequest:
                NavigationStack {
                    ArticleImportRequestView(state: state)
                }
            }
        }
        .task {
            await state.load()
        }
    }

    private var filteredPosts: [BlogPost] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return state.posts }
        return state.posts.filter { post in
            [
                post.title,
                post.translation?.title ?? "",
                post.authorName,
                post.authorHandle ?? "",
                post.plainText,
                post.translation?.plainText ?? ""
            ].contains { $0.lowercased().contains(normalized) }
        }
    }

    @ViewBuilder
    private var articleList: some View {
        if state.posts.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("記事はまだありません", systemImage: "doc.richtext")
            } description: {
                Text("Xの記事URLを送ると、読み取り完了後にここへ追加されます。")
            } actions: {
                Button("記事を追加") {
                    state.resetImportRequest()
                    presentedSheet = .importRequest
                }
                .buttonStyle(.borderedProminent)
            }
        } else if filteredPosts.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(filteredPosts) { post in
                NavigationLink(value: AppRoute.article(id: post.id)) {
                    ArticleListRow(post: post)
                }
                .accessibilityIdentifier("article-row-\(post.id)")
            }
            .listStyle(.plain)
            .refreshable {
                await state.load()
            }
        }
    }
}

private enum ArticleListSheet: String, Identifiable {
    case importRequest

    var id: String { rawValue }
}

@MainActor
private struct ArticleImportRequestView: View {
    let state: BlogPostState

    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var selectedHostId: String?
    @State private var translationMode: XArticleTranslationMode?

    private var readyHosts: [XArticleImportHost] {
        state.importHosts.filter(\.canImportXArticle)
    }

    private var canSubmit: Bool {
        guard selectedHostId != nil, translationMode != nil else { return false }
        return (try? XArticleImportRequest.normalizedSourceURL(sourceURL)) != nil
    }

    var body: some View {
        Group {
            if case .submitted(let task) = state.importRequestState {
                submittedContent(task)
            } else {
                requestForm
            }
        }
        .navigationTitle("記事を追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
            if case .submitted = state.importRequestState {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if case .submitting = state.importRequestState {
                            ProgressView()
                        } else {
                            Text("依頼")
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .accessibilityIdentifier("article-import-submit")
                }
            }
        }
        .task {
            if case .idle = state.importHostsState {
                await state.loadImportHosts()
            }
        }
        .onDisappear {
            state.resetImportRequest()
        }
    }

    private var isSubmitting: Bool {
        if case .submitting = state.importRequestState { return true }
        return false
    }

    private var requestForm: some View {
        Form {
            Section("X記事URL") {
                TextField(
                    "https://x.com/ユーザー名/status/記事ID",
                    text: $sourceURL,
                    axis: .vertical
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2 ... 4)
                .accessibilityIdentifier("article-import-url")

                if !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   (try? XArticleImportRequest.normalizedSourceURL(sourceURL)) == nil {
                    Label(
                        "Xのstatus URLを入力してください。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("実行PC") {
                switch state.importHostsState {
                case .idle, .loading:
                    HStack {
                        ProgressView()
                        Text("実行可能なPCを確認しています")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.red)
                    Button("再試行") {
                        Task { await state.loadImportHosts() }
                    }
                case .loaded:
                    if readyHosts.isEmpty {
                        Label(
                            "X Agentを実行できるオンラインPCがありません。",
                            systemImage: "desktopcomputer.trianglebadge.exclamationmark"
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        Picker("PC", selection: $selectedHostId) {
                            Text("選択してください")
                                .tag(nil as String?)
                            ForEach(readyHosts) { host in
                                Text(host.displayName)
                                    .tag(Optional(host.id))
                            }
                        }
                        .accessibilityIdentifier("article-import-host")
                    }

                    ForEach(state.importHosts.filter { !$0.canImportXArticle }) { host in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(host.displayName)
                                .font(.caption)
                            Text(hostUnavailableReason(host))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("保存内容") {
                Picker("翻訳", selection: $translationMode) {
                    Text("選択してください")
                        .tag(nil as XArticleTranslationMode?)
                    ForEach(XArticleTranslationMode.allCases) { mode in
                        Text(mode.label)
                            .tag(Optional(mode))
                    }
                }
                .accessibilityIdentifier("article-import-translation")

                if translationMode == .japanese {
                    Text("原文を保存したあと、記事全体の日本語訳も作成します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if translationMode == .originalOnly {
                    Text("Xの記事本文だけを保存します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = state.importRequestState {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(isSubmitting)
    }

    private func submittedContent(_ task: XArticleImportTask) -> some View {
        ContentUnavailableView {
            Label("読み取りを依頼しました", systemImage: "checkmark.circle.fill")
        } description: {
            Text("X Agentで記事を収集中です。保存とアップロードが終わると通知が届き、記事タブから読めます。")
        } actions: {
            Text("リクエストID: \(task.id)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private func submit() {
        guard let selectedHostId, let translationMode else { return }
        Task {
            await state.submitImportRequest(
                hostId: selectedHostId,
                sourceURL: sourceURL,
                translationMode: translationMode
            )
        }
    }

    private func hostUnavailableReason(_ host: XArticleImportHost) -> String {
        if host.status != .online {
            return host.status.label
        }
        return "不足: \(host.missingImportTags.joined(separator: ", "))"
    }
}

private struct ArticleListRow: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(post.preferredTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if post.translation != nil {
                    Image(systemName: "character.book.closed")
                        .foregroundStyle(post.translationState == .stale ? .orange : .secondary)
                        .accessibilityLabel(
                            post.translationState == .stale ? "日本語訳は更新前です" : "日本語訳あり"
                        )
                }
            }

            Text(post.preferredPlainText.replacingOccurrences(of: "\n", with: " "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(post.authorHandle.map { "@\($0)" } ?? post.authorName)
                Text("·")
                Text((post.publishedAt ?? post.importedAt).formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

@MainActor
struct ArticleDetailView: View {
    let id: String
    let state: BlogPostState

    var body: some View {
        Group {
            switch state.detailState {
            case .idle, .loading:
                ProgressView("記事を読み込んでいます")
            case .failed(let message):
                ContentUnavailableView {
                    Label("記事を開けません", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(message)
                } actions: {
                    Button("再試行") {
                        Task { await state.loadDetail(id: id) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loaded(let post):
                ArticleReaderView(post: post)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            await state.loadDetail(id: id)
        }
    }
}

private enum ArticleReaderLanguage: String, CaseIterable, Identifiable {
    case original
    case japanese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "原文"
        case .japanese: return "日本語"
        }
    }
}

private struct ArticleReaderView: View {
    let post: BlogPost

    @Environment(\.openURL) private var openURL
    @State private var language: ArticleReaderLanguage

    init(post: BlogPost) {
        self.post = post
        _language = State(initialValue: post.translation == nil ? .original : .japanese)
    }

    private var title: String {
        language == .japanese ? post.translation?.title ?? post.title : post.title
    }

    private var blocks: [BlogPostBlock] {
        language == .japanese ? post.translation?.body ?? post.body : post.body
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if post.translationState == .stale, language == .japanese {
                    Label(
                        "原文の更新前に作られた日本語訳です。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                if let coverImageUrl = post.coverImageUrl, let url = URL(string: coverImageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 180)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Text(post.authorName)
                        if let authorHandle = post.authorHandle {
                            Text("@\(authorHandle)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)

                    Text((post.publishedAt ?? post.importedAt).formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        ArticleBlockView(block: block)
                    }
                }
                .textSelection(.enabled)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top) {
            if post.translation != nil {
                Picker("表示言語", selection: $language) {
                    ForEach(ArticleReaderLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let url = URL(string: post.originalUrl) {
                        openURL(url)
                    }
                } label: {
                    Label("Xで開く", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}

private struct ArticleBlockView: View {
    let block: BlogPostBlock

    var body: some View {
        switch block {
        case .heading(let level, let children):
            Text(attributedText(children))
                .font(headingFont(level))
                .padding(.top, level == 1 ? 10 : 4)
        case .paragraph(let children):
            Text(attributedText(children))
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
        case .blockquote(let children):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 3)
                Text(attributedText(children))
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(.secondary)
            }
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .fontWeight(.semibold)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(attributedText(item))
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                    }
                }
            }
        case .image(let url, let alt, let caption):
            VStack(alignment: .leading, spacing: 6) {
                if let imageURL = URL(string: url) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 140)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            Label(alt.isEmpty ? "画像を読み込めません" : alt, systemImage: "photo")
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .divider:
            Divider()
                .padding(.vertical, 6)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            return .system(.title, design: .serif, weight: .bold)
        case 2:
            return .system(.title2, design: .serif, weight: .bold)
        default:
            return .system(.title3, design: .serif, weight: .semibold)
        }
    }

    private func attributedText(_ inlines: [BlogPostInline]) -> AttributedString {
        inlines.reduce(into: AttributedString()) { result, inline in
            var segment = AttributedString(inline.text)
            var intents: InlinePresentationIntent = []
            if inline.bold { intents.insert(.stronglyEmphasized) }
            if inline.italic { intents.insert(.emphasized) }
            if inline.strikethrough { intents.insert(.strikethrough) }
            if !intents.isEmpty {
                segment.inlinePresentationIntent = intents
            }
            if let href = inline.href, let url = URL(string: href) {
                segment.link = url
            }
            result.append(segment)
        }
    }
}

#Preview("記事一覧") {
    NavigationStack {
        ArticleListRow(post: BlogPost.preview)
            .padding()
    }
}

private extension BlogPost {
    static let preview = BlogPost(
        id: "2b6f3a1d-6548-4d9a-80a1-6ddcab63aa90",
        sourceType: "x_article",
        sourceId: "2081415714636996844",
        originalUrl: "https://x.com/thedankoe/status/2081415714636996844",
        canonicalUrl: "https://x.com/thedankoe/article/2081415714636996844",
        title: "How To Fix Your Entire Life",
        authorName: "Dan Koe",
        authorHandle: "thedankoe",
        language: "en",
        publishedAt: Date(),
        coverImageUrl: nil,
        body: [
            .paragraph(children: [
                BlogPostInline(
                    text: "Build a life that compounds.",
                    bold: false,
                    italic: false,
                    strikethrough: false,
                    href: nil
                )
            ])
        ],
        plainText: "Build a life that compounds.",
        contentHash: String(repeating: "a", count: 64),
        importedAt: Date(),
        translation: nil,
        translationState: .missing,
        createdAt: Date(),
        updatedAt: Date()
    )
}
