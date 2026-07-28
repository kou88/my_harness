import SwiftUI
import UIKit

struct ZoomableImageViewer: View {
    let sourceURL: URL
    let accessibilityLabel: String

    @Environment(\.dismiss) private var dismiss
    @State private var loadState: ZoomableImageLoadState = .loading
    @State private var dismissalOffset: CGFloat = 0
    @State private var isClosing = false

    var body: some View {
        GeometryReader { proxy in
            let progress = dismissalProgress(in: proxy.size.height)

            ZStack {
                Color.black
                    .opacity(1 - (progress * 0.82))
                    .ignoresSafeArea()

                imageContent
                    .scaleEffect(1 - (progress * 0.12))
                    .offset(y: dismissalOffset)

                closeButton
                    .opacity(1 - progress)
            }
        }
        .presentationBackground(.clear)
        .statusBarHidden()
        .task(id: sourceURL) {
            await loadImage()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .tint(.white)
        case .loaded(let image):
            NativeZoomableImageView(
                image: image,
                accessibilityLabel: accessibilityLabel,
                onDismissDragChanged: updateDismissalOffset,
                onDismissDragEnded: finishDismissalDrag
            )
            .ignoresSafeArea()
        case .failed:
            ContentUnavailableView {
                Label("画像を読み込めません", systemImage: "photo")
            } description: {
                Text(accessibilityLabel)
            }
            .foregroundStyle(.white)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: closeImmediately) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("画像を閉じる")
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }

    private func loadImage() async {
        loadState = .loading

        do {
            let (data, response) = try await URLSession.shared.data(from: sourceURL)
            if let response = response as? HTTPURLResponse {
                guard (200 ..< 300).contains(response.statusCode) else {
                    loadState = .failed
                    return
                }
            }
            guard let image = UIImage(data: data), !Task.isCancelled else {
                loadState = .failed
                return
            }
            loadState = .loaded(image)
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed
        }
    }

    private func updateDismissalOffset(_ translation: CGFloat) {
        guard !isClosing else { return }
        dismissalOffset = translation
    }

    private func finishDismissalDrag(translation: CGFloat, velocity: CGFloat) {
        guard !isClosing else { return }

        let projectedTranslation = translation + (velocity * 0.16)
        let shouldDismiss =
            abs(translation) >= 120 ||
            abs(projectedTranslation) >= 220

        guard shouldDismiss else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                dismissalOffset = 0
            }
            return
        }

        isClosing = true
        let direction: CGFloat = projectedTranslation < 0 ? -1 : 1
        withAnimation(.easeOut(duration: 0.18)) {
            dismissalOffset = direction * 1_200
        } completion: {
            closeImmediately()
        }
    }

    private func dismissalProgress(in containerHeight: CGFloat) -> CGFloat {
        min(abs(dismissalOffset) / max(containerHeight * 0.62, 1), 1)
    }

    private func closeImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dismiss()
        }
    }
}

private enum ZoomableImageLoadState {
    case loading
    case loaded(UIImage)
    case failed
}

private struct NativeZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let accessibilityLabel: String
    let onDismissDragChanged: (CGFloat) -> Void
    let onDismissDragEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDismissDragChanged: onDismissDragChanged,
            onDismissDragEnded: onDismissDragEnded
        )
    }

    func makeUIView(context: Context) -> PhotoZoomScrollView {
        let scrollView = PhotoZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.imageView.image = image
        scrollView.imageView.accessibilityLabel = accessibilityLabel

        let doubleTapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)

        let dismissalGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDismissalPan(_:))
        )
        dismissalGesture.maximumNumberOfTouches = 1
        dismissalGesture.cancelsTouchesInView = false
        dismissalGesture.delegate = context.coordinator
        scrollView.addGestureRecognizer(dismissalGesture)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: PhotoZoomScrollView, context: Context) {
        context.coordinator.onDismissDragChanged = onDismissDragChanged
        context.coordinator.onDismissDragEnded = onDismissDragEnded
        scrollView.imageView.accessibilityLabel = accessibilityLabel

        guard scrollView.imageView.image !== image else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        scrollView.imageView.image = image
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var scrollView: PhotoZoomScrollView?
        var onDismissDragChanged: (CGFloat) -> Void
        var onDismissDragEnded: (CGFloat, CGFloat) -> Void

        init(
            onDismissDragChanged: @escaping (CGFloat) -> Void,
            onDismissDragEnded: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.onDismissDragChanged = onDismissDragChanged
            self.onDismissDragEnded = onDismissDragEnded
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            self.scrollView?.zoomContentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let scrollView = scrollView as? PhotoZoomScrollView else { return }
            scrollView.centerZoomedContent()
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            guard let scrollView = scrollView as? PhotoZoomScrollView else { return }
            scrollView.centerZoomedContent()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let scrollView,
                gestureRecognizer is UIPanGestureRecognizer,
                scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001,
                !scrollView.isZooming,
                let panGesture = gestureRecognizer as? UIPanGestureRecognizer
            else {
                return false
            }

            let velocity = panGesture.velocity(in: scrollView)
            return abs(velocity.y) > abs(velocity.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc
        func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.001 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(2.5, scrollView.maximumZoomScale)
            let tapPoint = gesture.location(in: scrollView.zoomContentView)
            let zoomSize = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            let zoomRect = CGRect(
                x: tapPoint.x - (zoomSize.width / 2),
                y: tapPoint.y - (zoomSize.height / 2),
                width: zoomSize.width,
                height: zoomSize.height
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }

        @objc
        func handleDismissalPan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView else { return }

            switch gesture.state {
            case .changed:
                onDismissDragChanged(gesture.translation(in: scrollView).y)
            case .ended:
                onDismissDragEnded(
                    gesture.translation(in: scrollView).y,
                    gesture.velocity(in: scrollView).y
                )
            case .cancelled, .failed:
                onDismissDragEnded(0, 0)
            default:
                break
            }
        }
    }
}

@MainActor
private final class PhotoZoomScrollView: UIScrollView {
    let zoomContentView = UIView()
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        decelerationRate = .fast
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        zoomContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomContentView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        zoomContentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            zoomContentView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            zoomContentView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            zoomContentView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            zoomContentView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            zoomContentView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            zoomContentView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            imageView.leadingAnchor.constraint(equalTo: zoomContentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: zoomContentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: zoomContentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: zoomContentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerZoomedContent()
    }

    func centerZoomedContent() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}
