import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

struct AIImportedVideo: Transferable, @unchecked Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let suffix = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString.lowercased()).appendingPathExtension(suffix)
            try FileManager.default.copyItem(at: received.file, to: target)
            return AIImportedVideo(url: target)
        }
    }
}

enum AIMediaProcessingError: LocalizedError {
    case unreadableImage, unreadableVideo, unsupportedVideoFormat, encodingFailed, tooManyImages
    var errorDescription: String? {
        switch self {
        case .unreadableImage: "画像を読み取れませんでした。別の画像を選んでください。"
        case .unreadableVideo: "動画を読み取れませんでした。別の動画を選んでください。"
        case .unsupportedVideoFormat: "現在はMP4動画のみ送信できます。動画形式を確認してください。"
        case .encodingFailed: "画像を送信用のJPEGへ変換できませんでした。"
        case .tooManyImages: "画像は4枚まで選択できます。"
        }
    }
}

enum AIMediaProcessor {
    static func image(data: Data, fileName: String) async throws -> AIComposerAttachment {
        try await Task.detached(priority: .userInitiated) {
            guard let source = UIImage(data: data) else { throw AIMediaProcessingError.unreadableImage }
            let encoded = try jpeg(source)
            let id = UUID().uuidString.lowercased()
            return AIComposerAttachment(id: id, kind: .image, fileName: fileName,
                contentType: "image/jpeg", data: encoded)
        }.value
    }

    static func video(url: URL, fileName: String) async throws -> AIComposerAttachment {
        defer { try? FileManager.default.removeItem(at: url) }
        return try await Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? Int, size > 0, size <= 32 * 1024 * 1024 else {
                throw AIMediaProcessingError.unreadableVideo
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "mp4" else { throw AIMediaProcessingError.unsupportedVideoFormat }
            let data = try Data(contentsOf: url)
            guard data.count >= 12, String(data: data[4..<8], encoding: .ascii) == "ftyp" else {
                throw AIMediaProcessingError.unreadableVideo
            }
            return AIComposerAttachment(id: UUID().uuidString.lowercased(), kind: .video,
                fileName: fileName, contentType: "video/mp4", data: data)
        }.value
    }

    private static func jpeg(_ source: UIImage) throws -> Data {
        let limit: CGFloat = 2048
        let longest = max(source.size.width, source.size.height)
        let scale = longest > limit ? limit / longest : 1
        let size = CGSize(width: max(1, source.size.width * scale), height: max(1, source.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.jpegData(compressionQuality: 0.82), data.count <= 8 * 1024 * 1024 else {
            throw AIMediaProcessingError.encodingFailed
        }
        return data
    }
}
