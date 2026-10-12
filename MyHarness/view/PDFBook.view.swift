import PDFKit
import SwiftUI

struct PDFBookView: UIViewRepresentable {
    let url: URL
    let pageCount: Int
    let rotations: [Int: Int]
    @Binding var page: Int
    @Binding var spread: Bool
    @Binding var error: String
    let onTap: () -> Void

    func makeUIView(context: Context) -> BookPDFView {
        let view = BookPDFView()
        view.displayDirection = .horizontal
        view.autoScales = true
        view.pageOverlayViewProvider = context.coordinator
        if let document = PDFDocument(url: url), !document.isLocked, document.pageCount == pageCount,
           let initial = document.page(at: page - 1) {
            view.document = document
            view.go(to: initial)
        } else {
            DispatchQueue.main.async { error = "PDFを開けません。端末から削除し、再ダウンロードしてください。" }
        }
        context.coordinator.observe(view)
        view.layoutChanged = { [weak coordinator = context.coordinator] in coordinator?.layoutChanged() }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped(_:)))
            swipe.direction = direction
            swipe.delegate = context.coordinator
            view.addGestureRecognizer(swipe)
        }
        return view
    }

    func updateUIView(_ view: BookPDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyRotations(rotations)
        context.coordinator.go(to: page)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ view: BookPDFView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, UIGestureRecognizerDelegate {
        var parent: PDFBookView
        private weak var view: BookPDFView?
        private var spread = false
        private var configured = false
        private var changingLayout = false
        private var layoutSize = CGSize.zero
        private var renderScale: CGFloat = 0
        private var images: [Int: UIImage] = [:]
        private var overlays: [Int: BookPageOverlay] = [:]
        private var preparation: Task<Void, Never>?
        private var renderer: BookPageRenderer?
        private var generation = 0
        private var selectedPage: Int
        private var appliedRotations: [Int: Int] = [:]

        init(_ parent: PDFBookView) {
            self.parent = parent
            selectedPage = parent.page
            super.init()
            do { renderer = try BookPageRenderer(url: parent.url) }
            catch { DispatchQueue.main.async { parent.error = error.localizedDescription } }
        }

        private var layout: BookPageLayout {
            BookPageLayout(pageCount: parent.pageCount, spread: spread)
        }
        private var fittedRenderScale: CGFloat {
            guard let view else { return 0 }
            return (view.scaleFactorForSizeToFit * view.traitCollection.displayScale * 1000).rounded(.up) / 1000
        }

        func observe(_ view: BookPDFView) {
            self.view = view
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewSelectionChanged] {
                NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: name, object: view)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(trimImages), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(releaseImages), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        }

        func layoutChanged() {
            guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let wantsSpread = view.traitCollection.userInterfaceIdiom == .pad && view.bounds.width > view.bounds.height
            guard !configured || layoutSize != view.bounds.size || spread != wantsSpread else {
                if renderScale != fittedRenderScale { prepare() }
                return
            }
            changingLayout = true
            configured = true
            layoutSize = view.bounds.size
            spread = wantsSpread
            // UIPageViewControllerはdisplayModeを無視するため、見開きでは使用しない。
            view.usePageViewController(!spread, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 16])
            view.displayMode = spread ? .twoUp : .singlePage
            view.displaysAsBook = spread
            view.autoScales = true
            if let target = view.document?.page(at: selectedPage - 1) { view.go(to: target) }
            view.scaleFactor = view.scaleFactorForSizeToFit
            changingLayout = false
            parent.spread = spread
            prepare()
        }

        func go(to number: Int) {
            guard number != selectedPage, let target = view?.document?.page(at: number - 1) else { return }
            selectedPage = number
            changingLayout = true
            view?.go(to: target)
            if let view { view.scaleFactor = view.scaleFactorForSizeToFit }
            changingLayout = false
            prepare()
        }

        func applyRotations(_ rotations: [Int: Int]) {
            guard appliedRotations != rotations, let view, let document = view.document else { return }
            changingLayout = true
            for number in Set(appliedRotations.keys).union(rotations.keys) {
                guard let page = document.page(at: number - 1) else { continue }
                page.rotation = (page.rotation - (appliedRotations[number] ?? 0) + (rotations[number] ?? 0) + 360) % 360
            }
            appliedRotations = rotations
            view.layoutDocumentView()
            if let selected = document.page(at: selectedPage - 1) { view.go(to: selected) }
            view.scaleFactor = view.scaleFactorForSizeToFit
            changingLayout = false
            prepare()
        }

        @objc private func changed(_ notification: Notification) {
            guard let view, !changingLayout else { return }
            if notification.name == .PDFViewPageChanged, let document = view.document, let current = view.currentPage {
                let number = document.index(for: current) + 1
                // 見開き内の右ページへの明示移動をPDFKitの左ページ通知で失わない。
                if !layout.visiblePages(selectedPage).contains(number) {
                    selectedPage = number
                    parent.page = number
                }
                prepare()
            }
            if notification.name == .PDFViewScaleChanged, renderScale != fittedRenderScale { prepare() }
            updateOverlays()
        }

        private func prepare(includeNeighbors: Bool = true) {
            guard configured, view != nil, let renderer else { return }
            let scale = fittedRenderScale
            guard scale > 0 else { return }
            if renderScale != scale { images.removeAll(); renderScale = scale }
            preparation?.cancel()
            generation += 1
            let request = generation
            let visible = layout.visiblePages(selectedPage)
            let prepared = includeNeighbors ? layout.preparedPages(selectedPage) : visible
            images = images.filter { prepared.contains($0.key) }
            updateOverlays()
            let order = Array(visible) + prepared.filter { !visible.contains($0) }.sorted {
                abs($0 - selectedPage) < abs($1 - selectedPage)
            }
            preparation = Task { [weak self] in
                for number in order {
                    guard let self, !Task.isCancelled, self.generation == request else { return }
                    if self.images[number] != nil { continue }
                    do {
                        let image = try await renderer.render(number: number, scale: scale)
                        guard !Task.isCancelled, self.generation == request else { return }
                        self.images[number] = image
                        self.updateOverlays()
                    } catch {
                        guard !Task.isCancelled, self.generation == request else { return }
                        self.parent.error = error.localizedDescription
                        return
                    }
                }
            }
        }

        private func updateOverlays() {
            guard let view else { return }
            let visible = layout.visiblePages(selectedPage)
            let visibleReady = visible.allSatisfy { images[$0] != nil }
            let nativeRendering = view.scaleFactor > view.scaleFactorForSizeToFit * 1.02 || view.currentSelection != nil
            for (number, overlay) in overlays {
                overlay.isHidden = nativeRendering
                // 左右を一緒に表示する。未描画ページは白地と待機表示にする。
                overlay.show(images[number], ready: !visible.contains(number) || visibleReady)
            }
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let document = view.document else { return nil }
            let number = document.index(for: page) + 1
            let overlay = BookPageOverlay()
            overlays[number] = overlay
            updateOverlays()
            return overlay
        }

        func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let document = view.document else { return }
            let number = document.index(for: page) + 1
            if overlays[number] === overlayView { overlays.removeValue(forKey: number) }
        }

        @objc private func releaseImages() {
            preparation?.cancel()
            generation += 1
            images.removeAll()
            updateOverlays()
        }
        @objc private func trimImages() {
            preparation?.cancel()
            generation += 1
            let visible = layout.visiblePages(selectedPage)
            images = images.filter { visible.contains($0.key) }
            updateOverlays()
            if !visible.allSatisfy({ images[$0] != nil }) { prepare(includeNeighbors: false) }
        }
        @objc private func resume() { prepare() }
        func stop() {
            releaseImages()
            overlays.removeAll()
            NotificationCenter.default.removeObserver(self)
            view?.layoutChanged = {}
            view?.pageOverlayViewProvider = nil
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            if (view.bounds.width * 0.25...view.bounds.width * 0.75).contains(location.x),
               (view.bounds.height * 0.2...view.bounds.height * 0.8).contains(location.y) {
                parent.onTap()
                return
            }
            guard view.scaleFactor <= view.scaleFactorForSizeToFit * 1.02 else { return }
            if location.x < view.bounds.width * 0.25 { parent.page = layout.previous(selectedPage) }
            else if location.x > view.bounds.width * 0.75 { parent.page = layout.next(selectedPage) }
        }

        @objc func swiped(_ gesture: UISwipeGestureRecognizer) {
            parent.page = gesture.direction == .left ? layout.next(selectedPage) : layout.previous(selectedPage)
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view else { return false }
            if gestureRecognizer is UISwipeGestureRecognizer {
                return spread && view.scaleFactor <= view.scaleFactorForSizeToFit * 1.02
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

final class BookPDFView: PDFView {
    var layoutChanged: () -> Void = {}
    override func layoutSubviews() {
        super.layoutSubviews()
        // PDFKitのレイアウト完了後に設定を更新し、SwiftUI描画中のBinding変更を避ける。
        DispatchQueue.main.async { [weak self] in self?.layoutChanged() }
    }
}

private final class BookPageOverlay: UIView {
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    init() {
        super.init(frame: .zero)
        backgroundColor = .white
        isUserInteractionEnabled = false
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        spinner.color = .darkGray
        addSubview(spinner)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); spinner.center = CGPoint(x: bounds.midX, y: bounds.midY) }
    func show(_ image: UIImage?, ready: Bool) {
        imageView.image = ready ? image : nil
        if imageView.image == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

/// メインのPDFViewとは別のPDFDocumentを専用actorで描画する。
private actor BookPageRenderer {
    private let document: PDFDocument
    init(url: URL) throws {
        guard let document = PDFDocument(url: url), !document.isLocked else { throw BookError.invalidFile }
        self.document = document
    }
    func render(number: Int, scale: CGFloat) throws -> UIImage {
        try Task.checkCancellation()
        guard let page = document.page(at: number - 1) else { throw BookError.invalidFile }
        // PDFKitがoverlayを回転する。描画専用documentだけを回転なしにして二重回転を防ぐ。
        page.rotation = 0
        page.displaysAnnotations = true
        let box = page.bounds(for: .cropBox)
        let size = CGSize(width: ceil(box.width * scale), height: ceil(box.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.scaleBy(x: size.width / box.width, y: size.height / box.height)
            context.interpolationQuality = .high
            page.draw(with: .cropBox, to: context)
        }
    }
}
