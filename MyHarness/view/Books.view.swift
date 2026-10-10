import PDFKit
import SwiftUI

private struct BookReading: Identifiable {
    let book: Book
    let url: URL
    var id: String { book.id }
}

struct BookShelfView: View {
    @State var state: BookState
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

    init(book: Book, url: URL, initialPage: Int, savePage: @escaping (Int) -> Void) {
        self.book = book; self.url = url; self.savePage = savePage
        _page = State(initialValue: initialPage); _pageInput = State(initialValue: String(initialPage))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFBookView(url: url, page: $page, error: $error)
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red).padding() }
                HStack {
                    Button { page -= 1 } label: { Image(systemName: "chevron.left") }.disabled(page <= 1).accessibilityLabel("前のページ")
                    Spacer()
                    TextField("ページ", text: $pageInput).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 55)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("移動先ページ")
                    Text("/ \(book.pageCount)").monospacedDigit()
                    Button("移動") { if let target = Int(pageInput), (1...book.pageCount).contains(target) { page = target } else { pageInput = String(page) } }
                    Spacer()
                    Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled(page >= book.pageCount).accessibilityLabel("次のページ")
                }.padding()
            }
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { savePage(page); dismiss() } } }
            .onChange(of: page) { _, value in pageInput = String(value); savePage(value) }
            .onChange(of: scenePhase) { _, phase in if phase != .active { savePage(page) } }
            .onDisappear { savePage(page) }
        }
    }
}

private struct PDFBookView: UIViewRepresentable {
    let url: URL
    @Binding var page: Int
    @Binding var error: String
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        if let document = PDFDocument(url: url), !document.isLocked, let initial = document.page(at: page - 1) {
            view.document = document; view.go(to: initial)
        } else { DispatchQueue.main.async { error = "PDFを開けません。端末から削除し、再ダウンロードしてください。" } }
        context.coordinator.observe(view)
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
    @MainActor final class Coordinator: NSObject {
        var parent: PDFBookView
        init(_ parent: PDFBookView) { self.parent = parent }
        func observe(_ view: PDFView) { NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .PDFViewPageChanged, object: view) }
        @objc func changed(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let document = view.document, let current = view.currentPage else { return }
            let number = document.index(for: current) + 1
            if parent.page != number { parent.page = number }
        }
    }
}
