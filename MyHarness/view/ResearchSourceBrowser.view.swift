import SafariServices
import SwiftUI

struct ResearchSourceDestination: Identifiable, Hashable {
    let url: URL

    var id: String { url.absoluteString }
}

struct ResearchSourceBrowser: UIViewControllerRepresentable {
    let destination: ResearchSourceDestination

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: destination.url)
    }

    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) {}
}
