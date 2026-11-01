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
