import PDFKit
import SwiftUI

@main struct BookReaderRegressionApp: App {
    private let url: URL
    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reader-regression.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        try! renderer.writePDF(to: url) { context in
            for number in 1...9 {
                context.beginPage()
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
        verifyNavigation()
    }
    var body: some Scene {
        WindowGroup {
            BookReaderView(book: Book(id: "9a5df0bc-b430-462e-82e1-231414d4ac0b", title: "見開き・高解像度描画の検証", fileName: "reader-regression.pdf", sha256: "fixture", sizeBytes: 0, pageCount: 9, status: "ready", createdAt: .now), url: url, initialPage: 2) { print("Reader position: \($0)") }
                .task { await verifyRasterCache() }
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
