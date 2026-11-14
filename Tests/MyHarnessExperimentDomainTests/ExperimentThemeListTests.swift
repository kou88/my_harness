import XCTest
@testable import MyHarnessExperimentDomain

final class ExperimentThemeListTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func themes(_ ids: Range<Int>) -> [ExperimentThemeSummary] {
        ids.map { id in ExperimentThemeSummary(id: String(id), title: "テーマ \(id)", status: .paused, hypothesisCount: 0,
                                             testingHypothesisCount: 0, openTaskCount: 0, lastActivityAt: now) }
    }

    func testSeventyEightThemesAndShortFinalPage() throws {
        var list = ExperimentThemeList()
        for offset in stride(from: 0, to: 78, by: 15) {
            let end = min(offset + 15, 78)
            try list.accept(.init(items: themes(offset..<end), total: 78, limit: 15, offset: offset), offset: offset, at: now)
            XCTAssertEqual(list.items.count, end)
            XCTAssertEqual(list.hasMore, end < 78)
        }
        XCTAssertEqual(list.items.map(\.id), (0..<78).map(String.init))
    }

    func testRetriesSameOffsetAndAdvancesPastDuplicatesAfterReorder() throws {
        var list = ExperimentThemeList()
        try list.accept(.init(items: themes(0..<15), total: 30, limit: 15, offset: 0), offset: 0, at: now)
        XCTAssertThrowsError(try list.accept(.init(items: [], total: 30, limit: 15, offset: 15), offset: 15, at: now))
        XCTAssertEqual(list.nextOffset, 15)
        XCTAssertEqual(list.items.count, 15)
        try list.accept(.init(items: themes(14..<29), total: 30, limit: 15, offset: 15), offset: 15, at: now)
        XCTAssertEqual(list.items.count, 29)
        XCTAssertEqual(list.nextOffset, 30)
        XCTAssertFalse(list.hasMore)
        try list.accept(.init(items: [], total: 0, limit: 15, offset: 0), offset: 0, at: now)
        XCTAssertTrue(list.items.isEmpty)
        XCTAssertTrue(list.isFresh(at: now))
        list.invalidate()
        XCTAssertFalse(list.isFresh(at: now))
    }

    @MainActor
    func testReturningToAnExpiredListKeepsAllLoadedPagesAndOnlyCachesTheFirst() async throws {
        var list = ExperimentThemeList()
        for offset in [0, 15, 30] {
            try list.accept(.init(items: themes(offset..<offset+15), total: 78, limit: 15, offset: offset), offset: offset, at: now)
        }
        let later = now.addingTimeInterval(301)
        XCTAssertFalse(list.isFresh(at: later))
        var requested: [Int] = []
        let result = try await list.refreshed(keeping: "32", at: later) { offset in
            requested.append(offset)
            return .init(items: self.themes(offset..<offset+15), total: 78, limit: 15, offset: offset)
        }
        XCTAssertEqual(requested, [0, 15, 30])
        XCTAssertEqual(result.list.items, list.items)
        XCTAssertEqual(result.list.nextOffset, 45)
        XCTAssertEqual(result.first.items.count, 15)
        XCTAssertTrue(result.list.isFresh(at: later))
    }

    @MainActor
    func testInsertionAtTheHeadKeepsAnOpenedThemeThatMovedToTheNextPage() async throws {
        var list = ExperimentThemeList()
        for offset in [0, 15] {
            try list.accept(.init(items: themes(offset..<offset+15), total: 60, limit: 15, offset: offset), offset: offset, at: now)
        }
        let reordered = themes(60..<64) + themes(0..<60)
        let result = try await list.refreshed(keeping: "29", at: now) { offset in
            .init(items: Array(reordered.dropFirst(offset).prefix(15)), total: reordered.count, limit: 15, offset: offset)
        }
        XCTAssertEqual(result.list.items[33].id, "29")
        XCTAssertEqual(result.list.nextOffset, 45)
        XCTAssertTrue(result.list.hasMore)
    }

    @MainActor
    func testFailureOnSecondPageLeavesTheOldWindowAndShrinkageTerminates() async throws {
        var list = ExperimentThemeList()
        for offset in [0, 15] {
            try list.accept(.init(items: themes(offset..<offset+15), total: 40, limit: 15, offset: offset), offset: offset, at: now)
        }
        do {
            _ = try await list.refreshed(keeping: "29", at: now) { offset in
                if offset == 15 { throw URLError(.notConnectedToInternet) }
                return .init(items: self.themes(0..<15), total: 40, limit: 15, offset: offset)
            }
            XCTFail("途中で通信が失敗した一覧を採用した")
        } catch let err as URLError { XCTAssertEqual(err.code, .notConnectedToInternet) }
        XCTAssertEqual(list.items.map(\.id), (0..<30).map(String.init))
        let result = try await list.refreshed(keeping: "29", at: now) { offset in
            let end = min(offset + 15, 18)
            return .init(items: self.themes(offset..<end), total: 18, limit: 15, offset: offset)
        }
        XCTAssertEqual(result.list.nextOffset, 18)
        XCTAssertFalse(result.list.hasMore)
    }

    func testColdStartReadsOnlyTheOwnersFirstPageAndExpires() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ExperimentThemePageCache(directory: dir)
        let page = ExperimentThemeList.FirstPage(ownerID: "alice", fetchedAt: now, items: themes(0..<15), total: 78)
        try cache.write(page)
        var list = ExperimentThemeList()
        list.restore(try XCTUnwrap(cache.read(owner: "alice", now: now)))
        XCTAssertTrue(list.isFresh(at: now.addingTimeInterval(299)))
        XCTAssertFalse(list.isFresh(at: now.addingTimeInterval(301)))
        XCTAssertEqual(list.nextOffset, 15)
        XCTAssertNotNil(cache.read(owner: "alice", now: now.addingTimeInterval(301)))
        XCTAssertNil(cache.read(owner: "bob", now: now))
        XCTAssertNil(cache.read(owner: "alice", now: now))
        try cache.write(page)
        XCTAssertNil(cache.read(owner: "alice", now: now.addingTimeInterval(86_400)))
        try Data("unreadable".utf8).write(to: cache.file)
        XCTAssertNil(cache.read(owner: "alice", now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.file.path))
    }
}
