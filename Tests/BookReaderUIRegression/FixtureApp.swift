import PDFKit
import SwiftUI

@main struct BookReaderRegressionApp: App {
    private let url: URL
    private let book: Book
    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reader-regression.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        try! renderer.writePDF(to: url) { context in
            for number in 1...9 {
                context.beginPage()
                if number == 9 {
                    let scan = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { image in
                        UIColor.white.setFill(); image.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                        ("SCANNED PAGE 9" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 45), .foregroundColor: UIColor.blue])
                        UIColor.red.setFill(); image.fill(CGRect(x: 80, y: 400, width: 120, height: 120))
                    }
                    scan.draw(in: CGRect(x: 0, y: 0, width: 600, height: 800))
                    continue
                }
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                let color = UIColor(hue: CGFloat(number) / 10, saturation: 0.65, brightness: 0.65, alpha: 1)
                ("PAGE \(number)" as NSString).draw(at: CGPoint(x: 40, y: 50), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 75), .foregroundColor: color])
                for line in 0..<27 {
                    ("\(number) / \(line)   Sharp PDF text: あいうえお ABC 0123456789" as NSString).draw(at: CGPoint(x: 40, y: 160 + line * 20), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                }
                context.cgContext.setStrokeColor(color.cgColor)
                context.cgContext.setLineWidth(0.25)
                context.cgContext.stroke(CGRect(x: 20, y: 20, width: 560, height: 760))
            }
        }
        let document = PDFDocument(url: url)!
        let annotation = PDFAnnotation(bounds: CGRect(x: 40, y: 50, width: 260, height: 40), forType: .square, withProperties: nil)
        annotation.interiorColor = .yellow
        annotation.color = .red
        document.page(at: 1)!.addAnnotation(annotation)
        document.page(at: 6)!.rotation = 90
        document.write(to: url)
        self.url = url
        let size = try! url.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        self.book = Book(id: "9a5df0bc-b430-462e-82e1-231414d4ac0b", title: "見開き・回転保存の検証", fileName: "reader-regression.pdf", sha256: try! BookStorage.digest(url), sizeBytes: Int64(size), pageCount: 9, status: "ready", createdAt: .now)
        verifyNavigation()
    }
    var body: some Scene {
        WindowGroup {
            BookReaderView(book: book, url: url, initialPage: 2, saveChanges: { book, prepared in
                try await FixtureBookCloud.save(book, revision: prepared)
            }) { print("Reader position: \($0)") }
                .task { await verifyRasterCache(); await verifyPageEditing() }
        }
    }
    private func verifyNavigation() {
        for count in 1...9 {
            for spread in [false, true] {
                let layout = BookPageLayout(pageCount: count, spread: spread)
                for page in 1...count {
                    let visible = layout.visiblePages(page)
                    assert(visible.contains(page))
                    assert(layout.preparedPages(page).contains(page))
                    assert((1...count).contains(layout.previous(page)))
                    assert((1...count).contains(layout.next(page)))
                    if visible.upperBound < count { assert(layout.next(page) > visible.upperBound) }
                    if visible.lowerBound > 1 { assert(layout.previous(page) < visible.lowerBound) }
                    assert(layout.preparedPages(page).lowerBound == max(1, visible.lowerBound - 2))
                    assert(layout.preparedPages(page).upperBound == min(count, visible.upperBound + 2))
                }
            }
        }
        let spread = BookPageLayout(pageCount: 9, spread: true)
        assert(spread.visiblePages(1) == 1...1)
        assert(spread.visiblePages(3) == 2...3)
        assert(spread.next(1) == 2 && spread.next(2) == 4 && spread.previous(4) == 2)
        print("Book navigation boundary checks passed")
    }

    @MainActor private func verifyPageEditing() async {
        let editor = BookRotationState(book: book, url: url)
        editor.rotate(1, clockwise: true)
        editor.rotate(2, clockwise: true)
        editor.rotate(7, clockwise: false)
        editor.rotate(9, clockwise: true)
        assert(editor.rotations == [1: 90, 2: 90, 7: 270, 9: 90])
        var attempts = 0
        var reservationID = ""
        let upload: (Book, BookPreparedRevision) async throws -> BookEdition = { original, prepared in
            attempts += 1
            if attempts == 1 {
                reservationID = prepared.id
                throw URLError(.networkConnectionLost)
            }
            assert(reservationID == prepared.id)
            let cover = UIImage(contentsOfFile: prepared.thumbnail.path)!
            assert(cover.size.width > cover.size.height)
            let source = PDFDocument(url: self.url)!
            let edited = PDFDocument(url: prepared.pdf)!
            assert(edited.pageCount == 9)
            for index in 0..<9 {
                let expected = (source.page(at: index)!.rotation + ([1: 90, 2: 90, 7: 270, 9: 90][index + 1] ?? 0)) % 360
                assert(edited.page(at: index)!.rotation == expected)
                assert(edited.page(at: index)!.string == source.page(at: index)!.string)
            }
            edited.page(at: 8)!.rotation = 0
            assert(edited.page(at: 8)!.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox).pngData() == source.page(at: 8)!.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox).pngData())
            assert(edited.page(at: 1)!.annotations.count == source.page(at: 1)!.annotations.count)
            return try await FixtureBookCloud.save(original, revision: prepared)
        }
        await editor.save(using: upload)
        assert(!editor.error.isEmpty && editor.prepared != nil && editor.hasChanges)
        await editor.save(using: upload)
        assert(editor.error.isEmpty && !editor.hasChanges && editor.prepared == nil)
        try! BookStorage.verify(editor.url, book: editor.book)
        let local = try! BookStorage(ownerID: UUID().uuidString.lowercased())
        defer { try? FileManager.default.removeItem(at: local.directory) }
        let legacy = local.directory.appendingPathComponent("\(book.id).pdf")
        try! FileManager.default.copyItem(at: self.url, to: legacy)
        try! local.migrateLegacy(book)
        assert(local.isDownloaded(book))
        assert(!local.isDownloaded(editor.book))
        try! local.installVerified(editor.url, book: editor.book)
        assert(local.isDownloaded(editor.book))
        try! local.remove(editor.book)
        assert(!local.isDownloaded(book) && !local.isDownloaded(editor.book))
        print("Versioned cache checks passed: legacy migration, changed SHA invalidates cache, remove clears saved versions")
        assert(PDFDocument(url: self.url)!.page(at: 1)!.rotation == 0)
        let same = BookRotationState(book: book, url: url)
        for _ in 0..<4 { same.rotate(2, clockwise: true) }
        assert(!same.hasChanges)
        print("Page editing checks passed: only selected pages rotated, source intact, annotations preserved, retry uses same reservation")
    }

    @MainActor private func verifyRasterCache() async {
        func findPDF(_ view: UIView) -> PDFView? {
            if let pdf = view as? PDFView { return pdf }
            return view.subviews.lazy.compactMap { findPDF($0) }.first
        }
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            guard let pdf = windows.lazy.compactMap({ findPDF($0) }).first,
                  let provider = pdf.pageOverlayViewProvider else { continue }
            // 検証ホストだけが内部キャッシュを検査する。本番の公開APIには診断用口を増やさない。
            let values = Mirror(reflecting: provider).children
            guard let images = values.first(where: { $0.label == "images" })?.value as? [Int: UIImage] else { continue }
            let layout = BookPageLayout(pageCount: 9, spread: pdf.displayMode == .twoUp)
            let expected = Set(layout.preparedPages(2))
            guard Set(images.keys) == expected else { continue }
            for image in images.values {
                assert(image.size.width >= 600 * pdf.scaleFactorForSizeToFit * pdf.traitCollection.displayScale)
                assert(image.size.height >= 800 * pdf.scaleFactorForSizeToFit * pdf.traitCollection.displayScale)
            }
            let image = images[2]!
            let sample = image.cgImage!.cropping(to: CGRect(x: image.size.width * 0.15, y: image.size.height * 0.9125, width: 1, height: 1))!
            var rgba: [UInt8] = [0, 0, 0, 0]
            let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            assert(rgba[0] > 240 && rgba[1] > 240 && rgba[2] < 20, "黄色のPDF注釈が描画されていません: \(rgba)")
            print("Full-resolution cache checks passed: \(images.keys.sorted()), pixels: \(images[2]!.size)")
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            let trimmed = Mirror(reflecting: provider).children.first(where: { $0.label == "images" })!.value as! [Int: UIImage]
            assert(Set(trimmed.keys) == Set(layout.visiblePages(2)))
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            print("Memory pressure keeps visible pages and resumes prefetch")
            return
        }
        assertionFailure("前後2ページの画面解像度キャッシュが準備されませんでした")
    }
}

// 検証用の保存先。本番のAPIやアカウントを使わず、書き出した実PDFを別のURLへ保存する。
private enum FixtureBookCloud {
    static func save(_ book: Book, revision: BookPreparedRevision) async throws -> BookEdition {
        let updated = Book(id: book.id, title: book.title, fileName: book.fileName, sha256: revision.sha256, sizeBytes: revision.sizeBytes, pageCount: book.pageCount, status: "ready", createdAt: book.createdAt)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("saved-\(revision.id).pdf")
        if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: revision.pdf, to: target) }
        try BookStorage.verify(target, book: updated)
        return BookEdition(book: updated, url: target)
    }
}
