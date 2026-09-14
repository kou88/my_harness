import AVFoundation
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
    case unreadableImage, unreadableVideo, encodingFailed, tooManyImages
    var errorDescription: String? {
        switch self {
        case .unreadableImage: "画像を読み取れませんでした。別の画像を選んでください。"
        case .unreadableVideo: "動画を読み取れませんでした。別の動画を選んでください。"
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
            return AIComposerAttachment(id: id, kind: .image, groupId: id, fileName: fileName,
                contentType: "image/jpeg", frameIndex: 1, frameCount: 1, data: encoded)
        }.value
    }

    static func video(url: URL, fileName: String) async throws -> [AIComposerAttachment] {
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw AIMediaProcessingError.unreadableVideo }
        let frameCount = min(8, max(2, Int(ceil(seconds / 3))))
        let groupId = UUID().uuidString.lowercased()
        return try await Task.detached(priority: .userInitiated) {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 2048, height: 2048)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
            return try (0..<frameCount).map { index in
                let time = CMTime(seconds: seconds * (Double(index) + 0.5) / Double(frameCount), preferredTimescale: 600)
                let cgImage: CGImage
                do { cgImage = try generator.copyCGImage(at: time, actualTime: nil) }
                catch { throw AIMediaProcessingError.unreadableVideo }
                let encoded = try jpeg(UIImage(cgImage: cgImage))
                return AIComposerAttachment(id: UUID().uuidString.lowercased(), kind: .videoFrame, groupId: groupId,
                    fileName: fileName, contentType: "image/jpeg", frameIndex: index + 1, frameCount: frameCount, data: encoded)
            }
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
