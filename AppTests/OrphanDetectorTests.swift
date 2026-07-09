import XCTest
@testable import AAPSClientiOS

final class OrphanDetectorTests: XCTestCase {
    private let gracePeriodMs: Int64 = 60_000

    func test_noSignalWhenRosterIsNil() {
        let result = OrphanDetector.evaluate(
            ownClientId: "c1", roster: nil,
            docSrvModifiedMs: 2_000_000, pairedAtMs: 1_000_000, nowMs: 3_000_000, gracePeriodMs: gracePeriodMs
        )
        XCTAssertEqual(result, .noSignal)
    }

    func test_authorizedWhenOwnIdInRoster() {
        let result = OrphanDetector.evaluate(
            ownClientId: "c1", roster: ["c1", "c2"],
            docSrvModifiedMs: 2_000_000, pairedAtMs: 1_000_000, nowMs: 3_000_000, gracePeriodMs: gracePeriodMs
        )
        XCTAssertEqual(result, .authorized)
    }

    func test_deferredWhenDocPredatesPairingWithinGrace() {
        // Doc modified at pairedAt + 30s (grace is 60s) — still within the race window.
        let result = OrphanDetector.evaluate(
            ownClientId: "c1", roster: ["c2"],
            docSrvModifiedMs: 1_030_000, pairedAtMs: 1_000_000, nowMs: 3_000_000, gracePeriodMs: gracePeriodMs
        )
        XCTAssertEqual(result, .deferred)
    }

    func test_orphanedWhenDocPastGraceAndOwnIdMissing() {
        // Doc modified at pairedAt + 90s (past the 60s grace).
        let result = OrphanDetector.evaluate(
            ownClientId: "c1", roster: ["c2"],
            docSrvModifiedMs: 1_090_000, pairedAtMs: 1_000_000, nowMs: 3_000_000, gracePeriodMs: gracePeriodMs
        )
        XCTAssertEqual(result, .orphaned)
    }

    func test_orphanedWhenNoPairedAtRecorded() {
        // pairedAtMs == 0 (unknown) skips the race guard entirely, matching Kotlin's `pairedAt > 0L` check.
        let result = OrphanDetector.evaluate(
            ownClientId: "c1", roster: ["c2"],
            docSrvModifiedMs: 500_000, pairedAtMs: 0, nowMs: 3_000_000, gracePeriodMs: gracePeriodMs
        )
        XCTAssertEqual(result, .orphaned)
    }

    func test_orphanedWhenDocSrvModifiedUnknown() {
        // docSrvModifiedMs == 0 (unknown) skips the race guard entirely, matching Kotlin's `docSrvModified > 0L` check.
        let result = OrphanDetector.evaluate(
            ownClientId: "c1", roster: ["c2"],
            docSrvModifiedMs: 0, pairedAtMs: 1_000_000, nowMs: 3_000_000, gracePeriodMs: gracePeriodMs
        )
        XCTAssertEqual(result, .orphaned)
    }
}
