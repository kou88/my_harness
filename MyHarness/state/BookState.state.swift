import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class BookState {
    private let api: ActionInboxAPIClient?
    private let auth: CognitoAuthSession?
    private let configurationError: String?
    private var storage: BookStorage?
    private var ownerID = ""
    private var catalog = BookCatalog(books: [], pages: [:])
    private var transfers: [String: Task<Void, Never>] = [:]
    var books: [Book] = []
    var covers: [String: UIImage] = [:]
    var downloaded: Set<String> = []
    var progress: [String: Double] = [:]
    var errors: [String: String] = [:]
    var message = ""
    var isLoading = false

    init(api: ActionInboxAPIClient?, auth: CognitoAuthSession?, configurationError: String?) {
        self.api = api; self.auth = auth; self.configurationError = configurationError
    }

    func clearSession() {
        for transfer in transfers.values { transfer.cancel() }
        transfers = [:]; progress = [:]; errors = [:]; covers = [:]; downloaded = []; books = []
        storage = nil; ownerID = ""; catalog = BookCatalog(books: [], pages: [:]); message = ""
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let api, let auth else { throw BookError.unavailable(configurationError ?? "本棚が設定されていません") }
            let owner = try auth.bookOwnerID()
            if owner != ownerID {
                for transfer in transfers.values { transfer.cancel() }
                transfers = [:]; progress = [:]; errors = [:]; covers = [:]; downloaded = []; books = []
                storage = nil; ownerID = ""
                let local = try BookStorage(ownerID: owner)
                catalog = try local.load(); storage = local; ownerID = owner; books = catalog.books
                for book in books {
                    if local.isDownloaded(book) { downloaded.insert(book.id) }
                    if let image = UIImage(contentsOfFile: local.coverURL(book).path) { covers[book.id] = image }
                }
            }
            let fetched = try await api.fetchBooks()
            guard ownerID == owner, try auth.bookOwnerID() == owner else { return }
            catalog.books = fetched; books = fetched
            guard let storage else { throw BookError.unavailable("端末保存先がありません") }
            try storage.save(catalog)
            message = ""
            for book in books where covers[book.id] == nil {
                do {
                    let data = try await api.fetchBookCover(book)
                    guard let image = UIImage(data: data) else { throw BookError.unavailable("表紙を読み取れません") }
                    try data.write(to: storage.coverURL(book), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    guard ownerID == owner else { return }
                    covers[book.id] = image
                } catch { errors[book.id] = "表紙: \(error.localizedDescription)" }
            }
        } catch {
            if auth?.isSignedIn != true {
                for transfer in transfers.values { transfer.cancel() }
                books = []; covers = [:]; downloaded = []; storage = nil; ownerID = ""
            }
            message = books.isEmpty ? error.localizedDescription : "端末に保存した一覧を表示しています。\(error.localizedDescription)"
        }
    }

    func download(_ book: Book) {
        guard transfers[book.id] == nil, !downloaded.contains(book.id) else { return }
        errors[book.id] = nil; progress[book.id] = 0
        transfers[book.id] = Task {
            defer { transfers[book.id] = nil; progress[book.id] = nil }
            do {
                guard let api, let storage else { throw BookError.unavailable("ログインして本棚を更新してください") }
                let owner = ownerID
                try storage.checkSpace(book)
                let request = try await api.bookDownloadRequest(book)
                let delegate = BookDownloadProgress { [weak self] bytes in
                    Task { @MainActor in self?.progress[book.id] = min(1, Double(bytes) / Double(book.sizeBytes)) }
                }
                let (file, response) = try await URLSession.shared.download(for: request, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: file) }
                guard let response = response as? HTTPURLResponse else { throw BookError.unavailable("ダウンロード応答を確認できません") }
                guard response.statusCode == 200 else { throw BookError.http(response.statusCode) }
                try Task.checkCancellation()
                try await Task.detached(priority: .userInitiated) { try BookStorage.verify(file, book: book) }.value
                try Task.checkCancellation()
                guard ownerID == owner, try auth?.bookOwnerID() == owner else { throw CancellationError() }
                try storage.installVerified(file, book: book)
                downloaded.insert(book.id)
            } catch is CancellationError {
                errors[book.id] = nil
            } catch let error as URLError where error.code == .cancelled {
                errors[book.id] = nil
            } catch { errors[book.id] = error.localizedDescription }
        }
    }

    func cancel(_ book: Book) { transfers[book.id]?.cancel() }
    func remove(_ book: Book) {
        do {
            guard let storage else { throw BookError.unavailable("端末保存先がありません") }
            try storage.remove(book); downloaded.remove(book.id); errors[book.id] = nil
        } catch { errors[book.id] = error.localizedDescription }
    }
    func readerURL(_ book: Book) throws -> URL {
        guard let storage, downloaded.contains(book.id), try auth?.bookOwnerID() == ownerID else { throw BookError.unavailable("ログインとダウンロード状態を確認してください") }
        return storage.pdfURL(book)
    }
    func lastPage(_ book: Book) -> Int { catalog.pages[book.id] ?? 1 }
    func savePage(_ page: Int, book: Book) {
        guard (1...book.pageCount).contains(page) else { return }
        do {
            guard let storage else { throw BookError.unavailable("読書位置の保存先がありません") }
            catalog.pages[book.id] = page; try storage.save(catalog)
        } catch { errors[book.id] = error.localizedDescription }
    }
}
