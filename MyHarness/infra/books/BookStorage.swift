import CryptoKit
import Foundation
import PDFKit

struct BookStorage {
    let directory: URL

    init(ownerID: String) throws {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let owner = SHA256.hash(data: Data(ownerID.utf8)).map { String(format: "%02x", $0) }.joined()
        directory = root.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(owner, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    func pdfURL(_ book: Book) -> URL { directory.appendingPathComponent("\(book.id)-\(book.sha256).pdf") }
    func coverURL(_ book: Book) -> URL { directory.appendingPathComponent("\(book.id)-\(book.sha256).jpg") }
    /// 既存TestFlightの保存済みPDFを検証して版別ファイル名へ移す。
    func migrateLegacy(_ book: Book) throws {
        let legacy = directory.appendingPathComponent(book.id).appendingPathExtension("pdf")
        if FileManager.default.fileExists(atPath: legacy.path), !isDownloaded(book) {
            try Self.verify(legacy, book: book)
            try FileManager.default.moveItem(at: legacy, to: pdfURL(book))
        }
        let cover = directory.appendingPathComponent(book.id).appendingPathExtension("jpg")
        if FileManager.default.fileExists(atPath: cover.path), !FileManager.default.fileExists(atPath: coverURL(book).path) {
            try FileManager.default.moveItem(at: cover, to: coverURL(book))
        }
    }
    func isDownloaded(_ book: Book) -> Bool { FileManager.default.fileExists(atPath: pdfURL(book).path) }
    func load() throws -> BookCatalog {
        let url = directory.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return BookCatalog(books: [], pages: [:]) }
        return try JSONDecoder().decode(BookCatalog.self, from: Data(contentsOf: url))
    }
    func save(_ catalog: BookCatalog) throws {
        try JSONEncoder().encode(catalog).write(to: directory.appendingPathComponent("catalog.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func remove(_ book: Book) throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.pathExtension == "pdf" && (file.lastPathComponent == "\(book.id).pdf" || file.lastPathComponent.hasPrefix("\(book.id)-")) {
            try FileManager.default.removeItem(at: file)
        }
    }
    func checkSpace(_ book: Book) throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let free = attributes[.systemFreeSize] as? NSNumber else { throw BookError.unavailable("空き容量を確認できません") }
        if free.int64Value < book.sizeBytes * 2 { throw BookError.insufficientSpace }
    }
    static func verify(_ file: URL, book: Book) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, Int64(size) == book.sizeBytes else { throw BookError.invalidFile }
        let actual = try digest(file)
        guard actual == book.sha256, let pdf = PDFDocument(url: file), !pdf.isLocked, pdf.pageCount == book.pageCount else { throw BookError.invalidFile }
    }
    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func installVerified(_ source: URL, book: Book) throws {
        let destination = pdfURL(book)
        if FileManager.default.fileExists(atPath: destination.path) { try Self.verify(destination, book: book); return }
        let temporary = directory.appendingPathComponent(UUID().uuidString.lowercased()).appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

final class BookDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64) -> Void
    init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { progress(totalBytesWritten) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
