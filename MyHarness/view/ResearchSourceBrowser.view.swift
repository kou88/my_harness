import SwiftUI
import UIKit

struct ResearchSourceDestination: Identifiable, Hashable {
    let url: URL
    let applicationURL: URL?

    var id: String { url.absoluteString }

    init(url: URL, applicationURL: URL? = nil) {
        self.url = url
        self.applicationURL = applicationURL ?? Self.xApplicationURL(for: url)
    }

    init?(source: VentureResearchReportSource.External) {
        guard let url = source.destination else { return nil }
        self.init(url: url, applicationURL: source.applicationDestination)
    }

    private static func xApplicationURL(for url: URL) -> URL? {
        guard url.host?.lowercased() == "x.com" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let statusIndex = components.firstIndex(of: "status"),
              components.indices.contains(statusIndex + 1),
              !components[statusIndex + 1].isEmpty,
              var destination = URLComponents(string: "twitter://status") else {
            return nil
        }
        destination.queryItems = [URLQueryItem(name: "id", value: components[statusIndex + 1])]
        return destination.url
    }
}

struct ResearchSourceLinkButton<Label: View>: View {
    let destination: ResearchSourceDestination
    let label: Label

    init(destination: ResearchSourceDestination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        Button(action: open) {
            label
        }
        .buttonStyle(.borderless)
        .accessibilityHint(
            destination.applicationURL == nil
                ? "Safariで開きます"
                : "Xアプリを優先して開きます"
        )
    }

    private func open() {
        let targetURL: URL
        if let applicationURL = destination.applicationURL,
           UIApplication.shared.canOpenURL(applicationURL) {
            targetURL = applicationURL
        } else {
            targetURL = destination.url
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(targetURL)
        }
    }
}
