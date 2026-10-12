import CryptoKit
import Foundation
import PDFKit

struct BookEdition {
    let book: Book
    let url: URL
}

final class BookPreparedRevision: Sendable {
    let id: String
    let directory: URL
    let pdf: URL
    let thumbnail: URL
    let sha256: String
    let thumbnailSha256: String
    let sizeBytes: Int64
    let thumbnailSizeBytes: Int64

    init(id: String, directory: URL, pdf: URL, thumbnail: URL, sha256: String, thumbnailSha256: String, sizeBytes: Int64, thumbnailSizeBytes: Int64) {
        self.id = id; self.directory = directory; self.pdf = pdf; self.thumbnail = thumbnail
        self.sha256 = sha256; self.thumbnailSha256 = thumbnailSha256
        self.sizeBytes = sizeBytes; self.thumbnailSizeBytes = thumbnailSizeBytes
    }

    func removeTemporaryFiles() { try? FileManager.default.removeItem(at: directory) }
    deinit { removeTemporaryFiles() }
}

enum BookPDFEditor {
    static func prepare(url: URL, book: Book, rotations: [Int: Int]) throws -> BookPreparedRevision {
        try Task.checkCancellation()
        try BookStorage.verify(url, book: book)
        guard !rotations.isEmpty, let document = PDFDocument(url: url) else { throw BookError.invalidFile }
        for (number, degrees) in rotations {
            guard let page = document.page(at: number - 1), [90, 180, 270].contains(degrees) else { throw BookError.invalidFile }
            page.rotation = (page.rotation + degrees) % 360
        }
        let id = UUID().uuidString.lowercased()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let pdf = directory.appendingPathComponent("edited.pdf")
            let thumbnail = directory.appendingPathComponent("cover.jpg")
            guard document.write(to: pdf), let first = document.page(at: 0),
                  let cover = first.thumbnail(of: CGSize(width: 640, height: 900), for: .cropBox).jpegData(compressionQuality: 0.85) else { throw BookError.invalidFile }
            try cover.write(to: thumbnail, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: pdf.path)
            let size = try pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size <= 64 * 1024 * 1024, cover.count <= 1024 * 1024 else {
                throw BookError.unavailable("編集後のPDFまたは表紙が保存上限を超えています（PDF 64MiB・表紙1MiB）")
            }
            guard let saved = PDFDocument(url: pdf), saved.pageCount == book.pageCount else { throw BookError.invalidFile }
            for (number, _) in rotations {
                guard saved.page(at: number - 1)?.rotation == document.page(at: number - 1)?.rotation else { throw BookError.invalidFile }
            }
            try Task.checkCancellation()
            return BookPreparedRevision(id: id, directory: directory, pdf: pdf, thumbnail: thumbnail,
                sha256: try BookStorage.digest(pdf), thumbnailSha256: SHA256.hash(data: cover).map { String(format: "%02x", $0) }.joined(),
                sizeBytes: Int64(size), thumbnailSizeBytes: Int64(cover.count))
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
