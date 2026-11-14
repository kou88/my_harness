import Foundation
import Observation

@MainActor @Observable final class BookRotationState {
    var book: Book
    var url: URL
    var rotations: [Int: Int] = [:]
    var contentID = UUID()
    var isSaving = false
    var error = ""
    var message = ""
    private(set) var prepared: BookPreparedRevision?

    init(book: Book, url: URL) { self.book = book; self.url = url }
    var hasChanges: Bool { !rotations.isEmpty }
    var canRotate: Bool { !isSaving && prepared == nil }

    func rotate(_ page: Int, clockwise: Bool) {
        guard canRotate, (1...book.pageCount).contains(page) else { return }
        let degrees = ((rotations[page] ?? 0) + (clockwise ? 90 : 270)) % 360
        rotations[page] = degrees == 0 ? nil : degrees
        error = ""; message = ""
    }
    func discard() {
        guard !isSaving else { return }
        prepared?.removeTemporaryFiles(); prepared = nil
        rotations = [:]; error = ""; message = ""
        contentID = UUID()
    }
    func save(using upload: (Book, BookPreparedRevision) async throws -> BookEdition) async {
        guard hasChanges, !isSaving else { return }
        isSaving = true; error = ""; message = ""
        defer { isSaving = false }
        do {
            if prepared == nil {
                let source = url; let original = book; let changes = rotations
                prepared = try await Task.detached(priority: .userInitiated) {
                    try BookPDFEditor.prepare(url: source, book: original, rotations: changes)
                }.value
            }
            try Task.checkCancellation()
            guard let prepared else { throw BookError.invalidFile }
            let edition = try await upload(book, prepared)
            self.book = edition.book; url = edition.url
            prepared.removeTemporaryFiles(); self.prepared = nil
            rotations = [:]; contentID = UUID()
            message = "クラウドに保存しました"
        } catch {
            self.error = "保存を完了できませんでした。再試行できます。\(error.localizedDescription)"
        }
    }
}
