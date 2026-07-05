import UIKit

@MainActor
final class PasteboardClipboardWriter: ClipboardWriter {
    func write(_ text: String) {
        UIPasteboard.general.string = text
    }
}

