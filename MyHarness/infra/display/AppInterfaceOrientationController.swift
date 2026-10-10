import UIKit

@MainActor
final class AppInterfaceOrientationController {
    static let shared = AppInterfaceOrientationController()

    private(set) var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func enterReading() {
        updatePhoneOrientations(.allButUpsideDown)
    }

    func leaveReading() {
        updatePhoneOrientations(.portrait)
    }

    func enterFullScreen() {
        updatePhoneOrientations(.landscape)
    }

    func leaveFullScreen() {
        updatePhoneOrientations(.portrait)
    }

    private func updatePhoneOrientations(_ orientations: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        supportedOrientations = orientations

        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = windowScenes.first(where: {
            $0.activationState == .foregroundActive
        }) ?? windowScenes.first else {
            return
        }

        windowScene.windows.forEach {
            $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: orientations)
        ) { _ in }
    }
}

