import XCTest
@testable import AAPSClientiOS

final class PeriodCacheTests: XCTestCase {

    func test_missingKeyReturnsNil() {
        let cache = PeriodCache<Int, String>(ttl: 60)
        XCTAssertNil(cache.value(for: 7))
    }

    func test_freshEntryIsReturned() {
        var cache = PeriodCache<Int, String>(ttl: 60)
        let now = Date()
        cache.store("seven-day-data", for: 7, now: now)
        XCTAssertEqual(cache.value(for: 7, now: now.addingTimeInterval(30)), "seven-day-data")
    }

    func test_expiredEntryReturnsNil() {
        var cache = PeriodCache<Int, String>(ttl: 60)
        let now = Date()
        cache.store("seven-day-data", for: 7, now: now)
        XCTAssertNil(cache.value(for: 7, now: now.addingTimeInterval(61)))
    }

    func test_entryAtExactTtlBoundaryIsExpired() {
        var cache = PeriodCache<Int, String>(ttl: 60)
        let now = Date()
        cache.store("seven-day-data", for: 7, now: now)
        XCTAssertNil(cache.value(for: 7, now: now.addingTimeInterval(60)))
    }

    func test_differentKeysAreIndependent() {
        var cache = PeriodCache<Int, String>(ttl: 60)
        let now = Date()
        cache.store("seven-day-data", for: 7, now: now)
        cache.store("thirty-day-data", for: 30, now: now)
        XCTAssertEqual(cache.value(for: 7, now: now), "seven-day-data")
        XCTAssertEqual(cache.value(for: 30, now: now), "thirty-day-data")
        XCTAssertNil(cache.value(for: 90, now: now))
    }

    func test_restoringSameKeyRefreshesCachedAt() {
        var cache = PeriodCache<Int, String>(ttl: 60)
        let now = Date()
        cache.store("stale", for: 7, now: now)
        cache.store("fresh", for: 7, now: now.addingTimeInterval(50))
        XCTAssertEqual(cache.value(for: 7, now: now.addingTimeInterval(70)), "fresh")
    }
}
