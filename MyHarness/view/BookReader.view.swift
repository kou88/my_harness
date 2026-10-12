import PDFKit
import SwiftUI

struct BookReaderView: View {
    let book: Book
    let url: URL
    let savePage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: Int
    @State private var pageInput: String
    @State private var error = ""
    @State private var controlsVisible = false
    @State private var spread = false
    @State private var previewDocument: PDFDocument?

    init(book: Book, url: URL, initialPage: Int, savePage: @escaping (Int) -> Void) {
        self.book = book; self.url = url; self.savePage = savePage
        _page = State(initialValue: initialPage); _pageInput = State(initialValue: String(initialPage))
    }

    private var layout: BookPageLayout { BookPageLayout(pageCount: book.pageCount, spread: spread) }

    var body: some View {
        ZStack {
            PDFBookView(url: url, pageCount: book.pageCount, page: $page, spread: $spread, error: $error) {
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
                            Button { page = layout.previous(page) } label: { Image(systemName: "chevron.left") }.disabled(page <= 1).accessibilityLabel("前のページ")
                            Spacer()
                            TextField("ページ", text: $pageInput).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 55)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("移動先ページ")
                            Text("/ \(book.pageCount)").monospacedDigit()
                            Button("移動") {
                                if let target = Int(pageInput), (1...book.pageCount).contains(target) { page = target }
                                else { pageInput = String(page) }
                            }
                            Spacer()
                            Button { page = layout.next(page) } label: { Image(systemName: "chevron.right") }.disabled(layout.visiblePages(page).upperBound >= book.pageCount).accessibilityLabel("次のページ")
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
        .task {
            AppInterfaceOrientationController.shared.enterReading()
            previewDocument = PDFDocument(url: url)
        }
        .onChange(of: page) { _, value in pageInput = String(value); savePage(value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { savePage(page) } }
        .onDisappear { savePage(page); AppInterfaceOrientationController.shared.leaveReading() }
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

