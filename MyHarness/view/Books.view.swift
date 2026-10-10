import PDFKit
import SwiftUI

private struct BookReading: Identifiable {
    let book: Book
    let url: URL
    var id: String { book.id }
}

struct BookShelfView: View {
    @State var state: BookState
    let authState: ActionInboxState
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var savedOnly = false
    @State private var reading: BookReading?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("ダウンロード済み", isOn: $savedOnly).toggleStyle(.switch)
                if !state.message.isEmpty { Text(state.message).font(.footnote).foregroundStyle(.secondary) }
                let visible = state.books.filter {
                    (!savedOnly || state.downloaded.contains($0.id)) && (search.isEmpty || $0.title.localizedStandardContains(search))
                }
                if state.isLoading && state.books.isEmpty { ProgressView("本棚を読み込み中") }
                else if visible.isEmpty { ContentUnavailableView(search.isEmpty ? "本がありません" : "該当する本がありません", systemImage: "books.vertical") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 16)], alignment: .leading, spacing: 24) {
                    ForEach(visible) { book in bookTile(book) }
                }
            }.padding()
        }
        .navigationTitle("本棚")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if authState.isSignedIn {
                        Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") {
                            Task { await authState.signOut(); state.clearSession() }
                        }
                    } else {
                        Button("ログイン", systemImage: "person.crop.circle") {
                            Task { await authState.signIn(); await state.refresh() }
                        }.disabled(authState.isSigningIn || !authState.isConfigured)
                    }
                } label: { Image(systemName: "person.crop.circle") }
                .accessibilityLabel("本棚のアカウント")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !authState.isSignedIn {
                VStack {
                    Button(authState.isSigningIn ? "ログイン中" : "ログイン") {
                        Task { await authState.signIn(); await state.refresh() }
                    }.buttonStyle(.borderedProminent).disabled(authState.isSigningIn || !authState.isConfigured)
                    if let message = authState.message { Text(message).font(.caption).foregroundStyle(.red) }
                }.padding().frame(maxWidth: .infinity).background(.bar)
            }
        }
        .searchable(text: $search, prompt: "タイトルで検索")
        .refreshable { await state.refresh() }
        .task { await state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("cognitoDidSignOut"))) { _ in
            reading = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await state.refresh() } } }
        .fullScreenCover(item: $reading) { selected in
            BookReaderView(book: selected.book, url: selected.url, initialPage: state.lastPage(selected.book)) {
                state.savePage($0, book: selected.book)
            }
        }
    }

    private func bookTile(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { openOrDownload(book) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    if let cover = state.covers[book.id] {
                        Image(uiImage: cover).resizable().scaledToFit().padding(3)
                    } else { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary) }
                }.aspectRatio(0.69, contentMode: .fit).clipped()
            }.buttonStyle(.plain).accessibilityLabel("\(book.title)を\(state.downloaded.contains(book.id) ? "読む" : "ダウンロード")")
            Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text("\(book.pageCount)ページ · \(ByteCountFormatter.string(fromByteCount: book.sizeBytes, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
            if let progress = state.progress[book.id] {
                ProgressView(value: progress)
                HStack {
                    Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
                    Spacer()
                    Button("キャンセル") { state.cancel(book) }.font(.caption)
                }
            } else if state.downloaded.contains(book.id) {
                HStack {
                    Button("読む", systemImage: "book") { openOrDownload(book) }
                    Spacer()
                    Menu { Button("端末から削除", systemImage: "trash", role: .destructive) { state.remove(book) } } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("\(book.title)の保存管理")
                }.font(.subheadline)
                Label("ダウンロード済み", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
            } else { Button("ダウンロード", systemImage: "icloud.and.arrow.down") { state.download(book) }.font(.subheadline) }
            if let error = state.errors[book.id] { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func openOrDownload(_ book: Book) {
        if state.downloaded.contains(book.id) {
            do { reading = BookReading(book: book, url: try state.readerURL(book)) }
            catch { state.errors[book.id] = error.localizedDescription }
        } else { state.download(book) }
    }
}

private struct BookReaderView: View {
    let book: Book
    let url: URL
    let savePage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: Int
    @State private var pageInput: String
    @State private var error = ""
    @State private var controlsVisible = true
    @State private var previewDocument: PDFDocument?

    init(book: Book, url: URL, initialPage: Int, savePage: @escaping (Int) -> Void) {
        self.book = book; self.url = url; self.savePage = savePage
        _page = State(initialValue: initialPage); _pageInput = State(initialValue: String(initialPage))
    }

    var body: some View {
        ZStack {
            PDFBookView(url: url, page: $page, error: $error) {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
            }.ignoresSafeArea()
            if controlsVisible {
                VStack(spacing: 0) {
                    HStack {
                        Button("閉じる", systemImage: "xmark") { savePage(page); dismiss() }.labelStyle(.iconOnly)
                        Spacer()
                        Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Button("全画面", systemImage: "arrow.up.left.and.arrow.down.right") { controlsVisible = false }.labelStyle(.iconOnly)
                    }.padding().background(.ultraThinMaterial)
                    Spacer()
                    VStack(spacing: 10) {
                        if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                        HStack {
                            Button { page -= 1 } label: { Image(systemName: "chevron.left") }.disabled(page <= 1).accessibilityLabel("前のページ")
                            Spacer()
                            TextField("ページ", text: $pageInput).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 55)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("移動先ページ")
                            Text("/ \(book.pageCount)").monospacedDigit()
                            Button("移動") {
                                if let target = Int(pageInput), (1...book.pageCount).contains(target) { page = target }
                                else { pageInput = String(page) }
                            }
                            Spacer()
                            Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled(page >= book.pageCount).accessibilityLabel("次のページ")
                        }
                        Slider(value: Binding(get: { Double(page) }, set: { page = Int($0.rounded()) }), in: 1...Double(max(2, book.pageCount)), step: 1)
                            .disabled(book.pageCount == 1).accessibilityLabel("ページ移動バー").accessibilityValue("\(page) / \(book.pageCount)")
                        if let previewDocument {
                            BookPageStrip(document: previewDocument, page: $page)
                        }
                    }.padding().background(.ultraThinMaterial)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .task { previewDocument = PDFDocument(url: url) }
        .onChange(of: page) { _, value in pageInput = String(value); savePage(value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { savePage(page) } }
        .onDisappear { savePage(page) }
    }
}

private struct BookPageStrip: View {
    let document: PDFDocument
    @Binding var page: Int
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(1...document.pageCount, id: \.self) { number in
                        Button { page = number } label: {
                            VStack(spacing: 3) {
                                BookPageThumbnail(document: document, number: number)
                                    .frame(width: 43, height: 60).clipped()
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(page == number ? Color.accentColor : Color.clear, lineWidth: 2))
                                Text(String(number)).font(.caption2).monospacedDigit()
                            }.padding(2)
                        }.buttonStyle(.plain).id(number).accessibilityLabel("\(number)ページへ移動")
                    }
                }
            }.scrollIndicators(.hidden).frame(height: 82)
                .onAppear { proxy.scrollTo(page, anchor: .center) }
                .onChange(of: page) { _, value in proxy.scrollTo(value, anchor: .center) }
        }
    }
}

private struct BookPageThumbnail: View {
    let document: PDFDocument
    let number: Int
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Rectangle().fill(.quaternary).overlay { ProgressView().controlSize(.mini) } }
        }.task {
            image = document.page(at: number - 1)?.thumbnail(of: CGSize(width: 86, height: 120), for: .cropBox)
        }
    }
}

private struct PDFBookView: UIViewRepresentable {
    let url: URL
    @Binding var page: Int
    @Binding var error: String
    let onTap: () -> Void
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage; view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 16])
        view.autoScales = true
        if let document = PDFDocument(url: url), !document.isLocked, let initial = document.page(at: page - 1) {
            view.document = document; view.go(to: initial)
        } else { DispatchQueue.main.async { error = "PDFを開けません。端末から削除し、再ダウンロードしてください。" } }
        context.coordinator.observe(view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        guard let document = view.document, let current = view.currentPage, document.index(for: current) + 1 != page,
              let target = document.page(at: page - 1) else { return }
        view.go(to: target)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) { NotificationCenter.default.removeObserver(coordinator) }
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFBookView
        init(_ parent: PDFBookView) { self.parent = parent }
        func observe(_ view: PDFView) { NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .PDFViewPageChanged, object: view) }
        @objc func changed(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let document = view.document, let current = view.currentPage else { return }
            let number = document.index(for: current) + 1
            if parent.page != number { parent.page = number }
        }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            if (view.bounds.width * 0.25...view.bounds.width * 0.75).contains(location.x),
               (view.bounds.height * 0.2...view.bounds.height * 0.8).contains(location.y) { parent.onTap() }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
