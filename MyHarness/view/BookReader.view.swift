import PDFKit
import SwiftUI

struct BookReaderView: View {
    private var book: Book { editor.book }
    private var url: URL { editor.url }
    let saveChanges: (Book, BookPreparedRevision) async throws -> BookEdition
    let savePage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: Int
    @State private var pageInput: String
    @State private var error = ""
    @State private var controlsVisible = false
    @State private var spread = false
    @State private var previewDocument: PDFDocument?
    @State private var editor: BookRotationState
    @State private var previewID = UUID()
    @State private var discardAction: DiscardAction?
    private enum DiscardAction { case close, reset }

    init(book: Book, url: URL, initialPage: Int,
         saveChanges: @escaping (Book, BookPreparedRevision) async throws -> BookEdition,
         savePage: @escaping (Int) -> Void) {
        self.saveChanges = saveChanges; self.savePage = savePage
        _editor = State(initialValue: BookRotationState(book: book, url: url))
        _page = State(initialValue: initialPage); _pageInput = State(initialValue: String(initialPage))
    }

    private var layout: BookPageLayout { BookPageLayout(pageCount: book.pageCount, spread: spread) }

    var body: some View {
        ZStack {
            PDFBookView(url: url, pageCount: book.pageCount, rotations: editor.rotations, page: $page, spread: $spread, error: $error) {
                if !editor.isSaving { withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() } }
            }.id(editor.contentID).ignoresSafeArea()
            if controlsVisible {
                VStack(spacing: 0) {
                    HStack {
                        Button("閉じる", systemImage: "xmark") {
                            if editor.hasChanges { discardAction = .close } else { savePage(page); dismiss() }
                        }.labelStyle(.iconOnly).disabled(editor.isSaving)
                        Spacer()
                        Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Button("全画面", systemImage: "arrow.up.left.and.arrow.down.right") { controlsVisible = false }.labelStyle(.iconOnly).disabled(editor.isSaving)
                    }.padding().background(.ultraThinMaterial)
                    Spacer()
                    VStack(spacing: 10) {
                        if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                        if !editor.error.isEmpty { Text(editor.error).font(.footnote).foregroundStyle(.red) }
                        if !editor.message.isEmpty { Text(editor.message).font(.footnote).foregroundStyle(.secondary) }
                        HStack {
                            Menu {
                                ForEach(Array(layout.visiblePages(page)), id: \.self) { number in
                                    Button("\(number)ページを右に90°回転", systemImage: "rotate.right") { rotate(number, clockwise: true) }.disabled(!editor.canRotate)
                                    Button("\(number)ページを左に90°回転", systemImage: "rotate.left") { rotate(number, clockwise: false) }.disabled(!editor.canRotate)
                                }
                                if editor.hasChanges {
                                    Divider()
                                    Button("変更を破棄", systemImage: "arrow.uturn.backward", role: .destructive) { discardAction = .reset }.disabled(editor.isSaving)
                                }
                            } label: { Label("回転", systemImage: "rotate.right") }
                            Spacer()
                            if editor.isSaving { ProgressView().accessibilityLabel("クラウドに保存中") }
                            else if editor.hasChanges { Text("\(editor.rotations.count)ページ未保存").font(.caption).foregroundStyle(.secondary) }
                            Button(editor.isSaving ? "保存中…" : "クラウドに保存") { Task { await editor.save(using: saveChanges) } }
                                .disabled(!editor.hasChanges || editor.isSaving)
                        }
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
                            BookPageStrip(document: previewDocument, page: $page).id(previewID)
                        }
                    }.padding().background(.ultraThinMaterial)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .task(id: editor.contentID) {
            AppInterfaceOrientationController.shared.enterReading()
            previewDocument = PDFDocument(url: url)
            previewID = UUID()
        }
        .alert("変更を破棄しますか？", isPresented: Binding(get: { discardAction != nil }, set: { if !$0 { discardAction = nil } }), presenting: discardAction) { action in
            Button("変更を破棄", role: .destructive) {
                editor.discard()
                if action == .close { savePage(page); dismiss() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text(editor.prepared == nil ? "回転したページを保存せず元に戻します。" : "保存結果が未確認です。クラウドに保存済みの変更は、破棄しても取り消されません。再試行すると保存結果を確認できます。")
        }
        .onChange(of: page) { _, value in pageInput = String(value); savePage(value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { savePage(page) } }
        .onDisappear { savePage(page); AppInterfaceOrientationController.shared.leaveReading() }
    }

    private func rotate(_ number: Int, clockwise: Bool) {
        guard editor.canRotate else { return }
        editor.rotate(number, clockwise: clockwise)
        if let target = previewDocument?.page(at: number - 1) { target.rotation = (target.rotation + (clockwise ? 90 : 270)) % 360 }
        previewID = UUID()
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
