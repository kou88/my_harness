import Foundation

enum SharedXImportCandidateStoreError: LocalizedError {
    case appGroupUnavailable
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "共有データの保存領域を開けません。"
        case .invalidStoredData:
            return "保存済みの取り込み候補を読み込めません。"
        }
    }
}

struct SharedXImportCandidateRepository {
    static let storageFileName = "shared-x-import-candidates-v1.json"

    private let fileURL: URL

    init(appGroupIdentifier: String) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedXImportCandidateStoreError.appGroupUnavailable
        }
        fileURL = containerURL.appendingPathComponent(Self.storageFileName, isDirectory: false)
    }

    func load() throws -> [SharedXImportCandidate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SharedXImportCandidate].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            throw SharedXImportCandidateStoreError.invalidStoredData
        }
    }

    func save(_ candidate: SharedXImportCandidate) throws {
        var candidates = try load()
        candidates.removeAll { $0.canonicalKey == candidate.canonicalKey }
        candidates.append(candidate)
        try persist(candidates)
    }

    func remove(id: String) throws {
        var candidates = try load()
        candidates.removeAll { $0.id == id }
        try persist(candidates)
    }

    private func persist(_ candidates: [SharedXImportCandidate]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(candidates.sorted { $0.createdAt > $1.createdAt })
        try data.write(to: fileURL, options: .atomic)
    }
}
