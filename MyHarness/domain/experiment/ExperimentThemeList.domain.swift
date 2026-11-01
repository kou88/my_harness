import Foundation

struct ExperimentThemeList {
    static let pageSize = 15
    static let freshInterval: TimeInterval = 5 * 60
    static let offlineInterval: TimeInterval = 24 * 60 * 60

    struct FirstPage: Codable {
        let ownerID: String
        let fetchedAt: Date
        let items: [ExperimentThemeSummary]
        let total: Int

        func isUsable(for owner: String, at now: Date) -> Bool {
            ownerID == owner && (0..<ExperimentThemeList.offlineInterval).contains(now.timeIntervalSince(fetchedAt))
                && total >= items.count && items.count == min(ExperimentThemeList.pageSize, total)
                && Set(items.map(\.id)).count == items.count
        }
    }

    private(set) var items: [ExperimentThemeSummary] = []
    private(set) var nextOffset = 0
    private(set) var total = 0
    private(set) var fetchedAt: Date?
    var hasMore: Bool { nextOffset < total }

    func isFresh(at now: Date) -> Bool {
        guard let fetchedAt else { return false }
        return (0..<Self.freshInterval).contains(now.timeIntervalSince(fetchedAt))
    }

    mutating func restore(_ page: FirstPage) {
        items = page.items
        nextOffset = page.items.count
        total = page.total
        fetchedAt = page.fetchedAt
    }

    mutating func invalidate() { fetchedAt = nil }

    mutating func accept(_ page: ExperimentPage<ExperimentThemeSummary>, offset: Int, at now: Date) throws {
        guard page.limit == Self.pageSize, page.offset == offset,
              offset == 0 || offset == nextOffset, page.total >= 0,
              page.items.count == min(Self.pageSize, max(0, page.total - offset)) else {
            throw CocoaError(.coderReadCorrupt)
        }
        if offset == 0 { items = []; fetchedAt = now }
        var seen = Set(items.map(\.id))
        items.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
        // Offset counts server rows, including a repeated ID after a concurrent reorder.
        nextOffset = offset + page.items.count
        total = page.total
    }
}

struct ExperimentThemePageCache {
    let file: URL
    init(directory: URL) { file = directory.appendingPathComponent("experiment-theme-page-v1.json") }

    func read(owner: String, now: Date) -> ExperimentThemeList.FirstPage? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let data = try? Data(contentsOf: file),
              let page = try? JSONDecoder().decode(ExperimentThemeList.FirstPage.self, from: data),
              page.isUsable(for: owner, at: now) else {
            clear()
            return nil
        }
        return page
    }

    func write(_ page: ExperimentThemeList.FirstPage) throws {
        let data = try JSONEncoder().encode(page)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }

    func clear() { try? FileManager.default.removeItem(at: file) }
}
