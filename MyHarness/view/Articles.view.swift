import Foundation
import PhotosUI
import SwiftUI

@MainActor
struct ArticleListView: View {
    let state: BlogPostState

    @State private var query = ""
    @State private var presentedSheet: ArticleListSheet?

    var body: some View {
        List {
            articleHeader
            searchField
            importCandidateSection

            switch state.listState {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView("記事を読み込んでいます")
                    Spacer()
                }
                .listRowSeparator(.hidden)
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
                .listRowSeparator(.hidden)
            case .loaded:
                articleRows
            }
        }
        .listStyle(.plain)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            state.refreshImportCandidates()
            await state.load()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .importRequest:
                NavigationStack {
                    ArticleImportRequestView(state: state, source: .manual)
                }
            case .importCandidate(let candidate):
                NavigationStack {
                    ArticleImportRequestView(state: state, source: .shared(candidate))
                }
            }
        }
        .task {
            state.refreshImportCandidates()
            await state.load()
        }
    }

    private var articleHeader: some View {
        HStack(spacing: 12) {
            Text("記事")
                .font(.title2.weight(.bold))
            Spacer(minLength: 0)
            Button {
                state.resetImportRequest()
                presentedSheet = .importRequest
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("記事を追加")
            .accessibilityIdentifier("article-import-open")
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("タイトル・著者・本文を検索", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索をクリア")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
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
    private var importCandidateSection: some View {
        if !state.importCandidates.isEmpty {
            Section("取り込み候補  \(state.importCandidates.count)") {
                ForEach(state.importCandidates) { candidate in
                    Button {
                        state.resetImportRequest()
                        presentedSheet = .importCandidate(candidate)
                    } label: {
                        SharedXImportCandidateRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            state.removeImportCandidate(id: candidate.id)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                    .accessibilityIdentifier("article-import-candidate-\(candidate.id)")
                }
            }
        }

        if let message = state.importCandidateErrorMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var articleRows: some View {
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
            .listRowSeparator(.hidden)
        } else if filteredPosts.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowSeparator(.hidden)
        } else {
            ForEach(filteredPosts) { post in
                NavigationLink(value: AppRoute.article(id: post.id)) {
                    ArticleListRow(post: post)
                }
                .accessibilityIdentifier("article-row-\(post.id)")
            }
        }
    }
}

private enum ArticleListSheet: Identifiable {
    case importRequest
    case importCandidate(SharedXImportCandidate)

    var id: String {
        switch self {
        case .importRequest:
            return "import-request"
        case .importCandidate(let candidate):
            return "import-candidate-\(candidate.id)"
        }
    }
}

private enum ArticleImportRequestSource {
    case manual
    case shared(SharedXImportCandidate)

    var sourceURL: String {
        switch self {
        case .manual:
            return ""
        case .shared(let candidate):
            return candidate.sourceURL
        }
    }

    var candidate: SharedXImportCandidate? {
        switch self {
        case .manual:
            return nil
        case .shared(let candidate):
            return candidate
        }
    }
}

@MainActor
private struct ArticleImportRequestView: View {
    let state: BlogPostState
    let source: ArticleImportRequestSource

    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL: String
    @State private var selectedHostId: String?
    @State private var translationMode: XArticleTranslationMode?

    init(state: BlogPostState, source: ArticleImportRequestSource) {
        self.state = state
        self.source = source
        _sourceURL = State(initialValue: source.sourceURL)
    }

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
                translationMode: translationMode,
                candidate: source.candidate
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

private struct SharedXImportCandidateRow: View {
    let candidate: SharedXImportCandidate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.sourceText ?? "Xで共有した投稿")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(candidate.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("取り込み候補、\(candidate.sourceText ?? candidate.sourceURL)")
        .accessibilityHint("ダブルタップで読み取り設定を開きます")
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
    let authenticationRevision: Int
    @Environment(AppRouter.self) private var router

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
                    if !state.isSignedIn {
                        Button("ログインへ") { router.selectedTab = .nextActions }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("再試行") {
                        Task { await state.loadDetail(id: id) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loaded(let post):
                ArticleReaderView(post: post, state: state)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(id):\(authenticationRevision)") {
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
    let state: BlogPostState

    @Environment(\.openURL) private var openURL
    @State private var language: ArticleReaderLanguage
    @State private var presentedImage: ArticleImagePresentation?
    @State private var selectedReportImage: PhotosPickerItem?
    @State private var reportImageAlt = ""
    @State private var reportImageMessage: String?
    @State private var isUploadingReportImage = false

    init(post: BlogPost, state: BlogPostState) {
        self.post = post
        self.state = state
        _language = State(initialValue: post.translation == nil ? .original : .japanese)
    }

    private var title: String {
        language == .japanese ? post.translation?.title ?? post.title : post.title
    }

    private var blocks: [BlogPostBlock] {
        language == .japanese ? post.translation?.body ?? post.body : post.body
    }

    private var reportMarkdown: String {
        language == .japanese ? post.translation?.plainText ?? post.plainText : post.plainText
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
                    Button {
                        presentedImage = ArticleImagePresentation(
                            url: url,
                            accessibilityLabel: "\(title)のカバー画像"
                        )
                    } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title)のカバー画像")
                    .accessibilityHint("ダブルタップで全画面表示します")
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

                if post.sourceType == "research_report" {
                    HStack {
                        TextField("画像の説明", text: $reportImageAlt)
                            .textFieldStyle(.roundedBorder)
                        PhotosPicker(selection: $selectedReportImage, matching: .images) {
                            Label("画像を追加", systemImage: "photo.badge.plus")
                        }
                        .disabled(isUploadingReportImage)
                        .onChange(of: selectedReportImage) { _, selected in
                            guard let selected else { return }
                            Task {
                                isUploadingReportImage = true
                                defer { isUploadingReportImage = false; selectedReportImage = nil }
                                do {
                                    guard let data = try await selected.loadTransferable(type: Data.self),
                                          let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) else {
                                        throw ActionInboxAPIClient.ClientError.invalidResponse
                                    }
                                    try await state.addArticleImage(post: post, jpeg: jpeg,
                                        alt: reportImageAlt.isEmpty ? "記事画像" : reportImageAlt)
                                    reportImageMessage = "画像を記事の末尾に追加しました。"
                                } catch { reportImageMessage = error.localizedDescription }
                            }
                        }
                    }
                    if isUploadingReportImage { ProgressView("画像を保存中") }
                    if let reportImageMessage { Text(reportImageMessage).font(.caption).foregroundStyle(.secondary) }
                    ReportArticleMarkdownView(markdown: reportMarkdown, postID: post.id, title: title, state: state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            ArticleBlockView(block: block) { url, label in
                                presentedImage = ArticleImagePresentation(
                                    url: url,
                                    accessibilityLabel: label
                                )
                            }
                        }
                    }
                    .textSelection(.enabled)
                }
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
                if post.sourceType == "research_report" {
                    if let url = URL(string: post.canonicalUrl) {
                        ShareLink(item: url) {
                            Label("Webの記事URL", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Button {
                        if let url = URL(string: post.originalUrl) { openURL(url) }
                    } label: {
                        Label("Xで開く", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .fullScreenCover(item: $presentedImage) { image in
            ZoomableImageViewer(
                sourceURL: image.url,
                accessibilityLabel: image.accessibilityLabel
            )
        }
    }
}

private struct ReportArticleMarkdownView: View {
    let markdown: String
    let postID: String
    let title: String
    let state: BlogPostState
    @State private var expandedCompanies: Set<String> = []

    private enum ContentPart: Identifiable {
        case markdown(Int, String)
        case image(Int, String, String)
        var id: Int {
            switch self { case .markdown(let id, _), .image(let id, _, _): id }
        }
    }

    private func contentParts(_ source: String) -> [ContentPart] {
        let expression = try? NSRegularExpression(pattern: #"^!\[([^\]\n]{1,200})\]\(/api/blog-posts/([0-9A-Fa-f-]{36})/images/([0-9A-Fa-f-]{36})\)$"#)
        var parts: [ContentPart] = []
        var lines: [String] = []
        var inFence = false
        func flush() {
            let text = lines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(.markdown(parts.count, text))
            }
            lines.removeAll()
        }
        for line in source.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle() }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if !inFence, let match = expression?.firstMatch(in: line, range: range),
               let altRange = Range(match.range(at: 1), in: line),
               let postRange = Range(match.range(at: 2), in: line),
               let imageRange = Range(match.range(at: 3), in: line) {
                let referencedPost = String(line[postRange])
                let imageID = String(line[imageRange])
                if UUID(uuidString: referencedPost) != nil, UUID(uuidString: imageID) != nil,
                   referencedPost.caseInsensitiveCompare(postID) == .orderedSame {
                    flush()
                    parts.append(.image(parts.count, imageID, String(line[altRange])))
                    continue
                }
            }
            lines.append(line)
        }
        flush()
        return parts
    }

    @ViewBuilder
    private func articleContent(_ content: String, copyID: String) -> some View {
        ForEach(contentParts(content)) { part in
            switch part {
            case .markdown(let id, let text):
                AIChatMessageText(text: text, kind: .markdown, copyID: "\(copyID).\(id)")
            case .image(_, let imageID, let alt):
                PrivateReportImageView(state: state, postID: postID, imageID: imageID, alt: alt)
            }
        }
    }

    private struct Company: Identifiable {
        let id: String
        let title: String
        let markdown: String
    }

    private struct Group: Identifiable {
        let id: Int
        let introduction: String
        let companies: [Company]
    }

    private var sections: (introduction: String, groups: [Group]) {
        var introduction: [String] = []
        var groups: [Group] = []
        var groupLines: [String] = []
        var companies: [Company] = []
        var companyLines: [String] = []
        var companyTitle = ""
        var inDetails = false
        var fenceMarker: Character?
        var fenceLength = 0

        func appendContentLine(_ line: String) {
            if !inDetails { introduction.append(line) }
            else if companyTitle.isEmpty { groupLines.append(line) }
            else { companyLines.append(line) }
        }

        func finishCompany() {
            guard !companyTitle.isEmpty else { return }
            companies.append(Company(id: companyTitle, title: companyTitle,
                                     markdown: companyLines.joined(separator: "\n")))
            companyLines = []
            companyTitle = ""
        }
        func finishGroup() {
            finishCompany()
            guard !groupLines.isEmpty || !companies.isEmpty else { return }
            groups.append(Group(id: groups.count, introduction: groupLines.joined(separator: "\n"), companies: companies))
            groupLines = []
            companies = []
        }

        for (index, line) in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            if index == 0 && line == "# \(title)" { continue }
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let trimmed = line.dropFirst(leadingSpaces)
            let marker = trimmed.first
            let count = marker.map { symbol in trimmed.prefix(while: { $0 == symbol }).count } ?? 0
            if let open = fenceMarker {
                appendContentLine(line)
                if leadingSpaces <= 3 && marker == open && count >= fenceLength &&
                    trimmed.dropFirst(count).allSatisfy({ $0 == " " || $0 == "\t" }) {
                    fenceMarker = nil
                }
                continue
            }
            if leadingSpaces <= 3 && (marker == "`" || marker == "~") && count >= 3 {
                fenceMarker = marker
                fenceLength = count
                appendContentLine(line)
                continue
            }
            if line == "## 全100社の詳細" { inDetails = true }
            if !inDetails {
                introduction.append(line)
            } else if line.hasPrefix("## ") {
                finishGroup()
                groupLines.append(line)
            } else if line.hasPrefix("### P") {
                finishCompany()
                companyTitle = String(line.dropFirst(4))
            } else {
                appendContentLine(line)
            }
        }
        finishGroup()
        return (introduction.joined(separator: "\n"), groups)
    }

    var body: some View {
        let content = sections
        LazyVStack(alignment: .leading, spacing: 16) {
            articleContent(content.introduction, copyID: "report.\(postID).intro")
            ForEach(content.groups) { group in
                articleContent(group.introduction, copyID: "report.\(postID).group.\(group.id)")
                ForEach(group.companies) { company in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            if expandedCompanies.contains(company.id) {
                                expandedCompanies.remove(company.id)
                            } else {
                                expandedCompanies.insert(company.id)
                            }
                        } label: {
                            HStack {
                                Text(company.title).font(.headline).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: expandedCompanies.contains(company.id) ? "minus" : "plus")
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(company.title)の詳細を\(expandedCompanies.contains(company.id) ? "閉じる" : "開く")")
                        if expandedCompanies.contains(company.id) {
                            articleContent(company.markdown, copyID: "report.\(postID).\(company.id)")
                                .padding(.horizontal, 12)
                                .padding(.bottom, 14)
                        }
                    }
                    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct PrivateReportImageView: View {
    let state: BlogPostState
    let postID: String
    let imageID: String
    let alt: String
    @State private var image: UIImage?
    @State private var error = false
    @State private var expanded = false

    private func load() async {
        do {
            let data = try await state.loadArticleImage(postID: postID, imageID: imageID)
            guard let decoded = UIImage(data: data) else { throw ActionInboxAPIClient.ClientError.invalidResponse }
            image = decoded
            error = false
        } catch {
            self.error = true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Button { expanded = true } label: {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(alt)を拡大")
            } else if error {
                Button("\(alt)を再読み込み") { Task { await load() } }
            } else {
                ProgressView("\(alt)を読み込み中")
            }
            Text(alt).font(.caption).foregroundStyle(.secondary)
        }
        .task(id: imageID) { await load() }
        .fullScreenCover(isPresented: $expanded) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Button("閉じる") { expanded = false }
                    .padding().tint(.white)
            }
        }
    }
}

private struct ArticleBlockView: View {
    let block: BlogPostBlock
    let onImageTap: (URL, String) -> Void

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
                    Button {
                        onImageTap(imageURL, alt.isEmpty ? "記事内の画像" : alt)
                    } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityLabel(alt.isEmpty ? "記事内の画像" : alt)
                    .accessibilityHint("ダブルタップで全画面表示します")
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

private struct ArticleImagePresentation: Identifiable {
    let id: String
    let url: URL
    let accessibilityLabel: String

    init(url: URL, accessibilityLabel: String) {
        id = url.absoluteString
        self.url = url
        self.accessibilityLabel = accessibilityLabel
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
