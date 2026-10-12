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
