import XCTest
@testable import MyHarnessAIDomain

final class AIInferenceTests: XCTestCase {
    private let fixture = #"""
    {"hostId":"b884f804-cd11-4afc-af24-0ac248d36baa","hostName":"PC","online":true,"capturedAt":"2026-09-03T00:00:00Z",
     "desiredPolicy":{"revision":2,"maxConcurrentInferences":3,"models":[]},
     "state":{"policy":{"revision":1,"maxConcurrentInferences":3,"models":[]},"capabilities":[],"loadedModel":"q8","phase":"idle","error":"","reservedContextTokens":131072,
       "active":[{"id":"940dc690-0854-42c4-91cf-3347eb24203c","source":"api","model":"q8","contextLength":131072,"state":"draining","position":0,"waitSeconds":10,"reason":""}],
       "queued":[{"id":"25a9a3b4-2f3f-4ba2-a6bf-3cb6eebc4353","source":"chat","model":"q8","contextLength":65536,"state":"queued","position":1,"waitSeconds":3,"reason":"context_capacity"}]}}
    """#

    func testPendingPolicyIsNotShownAsAppliedUntilPcAcknowledges() throws {
        var host = try JSONDecoder().decode(AIInferenceHost.self, from: Data(fixture.utf8))
        XCTAssertFalse(host.isApplied)
        host.desiredPolicy = host.state.policy
        XCTAssertTrue(host.isApplied)
    }

    func testDisconnectAndCapacityWaitRemainDistinct() throws {
        let host = try JSONDecoder().decode(AIInferenceHost.self, from: Data(fixture.utf8))
        XCTAssertEqual(host.state.active.first?.statusText, "切断後の生成終了を確認中")
        XCTAssertEqual(host.state.queued.first?.statusText, "コンテキスト容量待ち")
        XCTAssertEqual(host.state.reservedContextTokens, 131072)
    }

    func testMissingAppliedPolicyDoesNotSilentlyInventState() {
        let incomplete = fixture.replacingOccurrences(of: #""policy":{"revision":1,"maxConcurrentInferences":3,"models":[]},"#, with: "")
        XCTAssertThrowsError(try JSONDecoder().decode(AIInferenceHost.self, from: Data(incomplete.utf8)))
    }
}
