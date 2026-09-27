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
    case unreadableImage, unreadableVideo, unsupportedVideoFormat, videoConversionFailed, videoTooLarge, encodingFailed, tooManyImages
    var errorDescription: String? {
        switch self {
        case .unreadableImage: "画像を読み取れませんでした。別の画像を選んでください。"
        case .unreadableVideo: "動画を読み取れませんでした。別の動画を選んでください。"
        case .unsupportedVideoFormat: "この動画はiPhone上でMP4に変換できません。別の動画を選んでください。"
        case .videoConversionFailed: "動画をMP4に変換できませんでした。別の動画を選んでください。"
        case .videoTooLarge: "動画はMP4への変換後も32 MiB以下のみ送信できます。短い動画を選んでください。"
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
            guard let size = attributes[.size] as? Int, size > 0 else { throw AIMediaProcessingError.unreadableVideo }
            let originalMP4 = url.pathExtension.lowercased() == "mp4" && isMP4(url: url)
            let outputURL = originalMP4 ? url : try await convertToMP4(url: url)
            defer { if !originalMP4 { try? FileManager.default.removeItem(at: outputURL) } }
            let outputAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            guard let outputSize = outputAttributes[.size] as? Int, outputSize > 0 else {
                throw AIMediaProcessingError.unreadableVideo
            }
            guard outputSize <= 32 * 1024 * 1024 else { throw AIMediaProcessingError.videoTooLarge }
            let data = try Data(contentsOf: outputURL)
            guard data.count >= 12, String(data: data[4..<8], encoding: .ascii) == "ftyp" else {
                throw AIMediaProcessingError.unreadableVideo
            }
            return AIComposerAttachment(id: UUID().uuidString.lowercased(), kind: .video,
                fileName: (fileName as NSString).deletingPathExtension + ".mp4", contentType: "video/mp4", data: data)
        }.value
    }

    private static func isMP4(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return false }
        return String(data: header[4..<8], encoding: .ascii) == "ftyp"
    }

    private static func convertToMP4(url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            throw AIMediaProcessingError.unsupportedVideoFormat
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality),
              session.supportedFileTypes.contains(.mp4) else {
            throw AIMediaProcessingError.unsupportedVideoFormat
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased()).appendingPathExtension("mp4")
        do {
            try await session.export(to: target, as: .mp4)
            return target
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw AIMediaProcessingError.videoConversionFailed
        }
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
