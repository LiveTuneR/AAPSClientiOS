import XCTest
@testable import AAPSClientiOS

final class BasalSegmentsTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int, _ min: Int, tz: TimeZone) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = h; c.minute = min
        var calendar = cal
        calendar.timeZone = tz
        return calendar.date(from: c)!
    }

    func test_singleBlockCoversWholeWindow() {
        let tz = TimeZone(identifier: "UTC")!
        let basal = [BasalEntry(startSeconds: 0, rate: 0.8)]
        let start = d(2026, 6, 22, 10, 0, tz: tz)
        let end = d(2026, 6, 22, 13, 0, tz: tz)
        let segs = basalSegments(basal: basal, windowStart: start, windowEnd: end, timeZone: tz)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].rate, 0.8)
        XCTAssertEqual(segs[0].start, start)
        XCTAssertEqual(segs[0].end, end)
    }

    func test_unsortedInputIsSortedBeforeBuildingSegments() {
        let tz = TimeZone(identifier: "UTC")!
        let basal = [
            BasalEntry(startSeconds: 7 * 3600, rate: 1.0),
            BasalEntry(startSeconds: 0, rate: 0.5),
            BasalEntry(startSeconds: 22 * 3600, rate: 0.3),
        ]
        let start = d(2026, 6, 22, 6, 0, tz: tz)
        let end = d(2026, 6, 22, 8, 0, tz: tz)
        let segs = basalSegments(basal: basal, windowStart: start, windowEnd: end, timeZone: tz)
            .sorted { $0.start < $1.start }
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].rate, 0.5)
        XCTAssertEqual(segs[0].start, start)
        XCTAssertEqual(segs[0].end, d(2026, 6, 22, 7, 0, tz: tz))
        XCTAssertEqual(segs[1].rate, 1.0)
        XCTAssertEqual(segs[1].start, d(2026, 6, 22, 7, 0, tz: tz))
        XCTAssertEqual(segs[1].end, end)
    }

    func test_windowSpanningTwoDaysProducesSegmentsOnBothDays() {
        let tz = TimeZone(identifier: "UTC")!
        let basal = [
            BasalEntry(startSeconds: 0, rate: 0.4),
            BasalEntry(startSeconds: 12 * 3600, rate: 0.9),
        ]
        let start = d(2026, 6, 21, 18, 0, tz: tz)
        let end = d(2026, 6, 22, 6, 0, tz: tz)
        let segs = basalSegments(basal: basal, windowStart: start, windowEnd: end, timeZone: tz)
            .sorted { $0.start < $1.start }
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].rate, 0.9)
        XCTAssertEqual(segs[0].start, start)
        XCTAssertEqual(segs[0].end, d(2026, 6, 22, 0, 0, tz: tz))
        XCTAssertEqual(segs[1].rate, 0.4)
        XCTAssertEqual(segs[1].start, d(2026, 6, 22, 0, 0, tz: tz))
        XCTAssertEqual(segs[1].end, end)
    }

    func test_negativeUtcOffsetDoesNotShiftDayBoundary() {
        let tz = TimeZone(identifier: "America/New_York")!
        let basal = [
            BasalEntry(startSeconds: 0, rate: 0.4),
            BasalEntry(startSeconds: 6 * 3600, rate: 0.9),
        ]
        let start = d(2026, 6, 22, 1, 0, tz: tz)
        let end = d(2026, 6, 22, 5, 0, tz: tz)
        let segs = basalSegments(basal: basal, windowStart: start, windowEnd: end, timeZone: tz)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].rate, 0.4)
        XCTAssertEqual(segs[0].start, start)
        XCTAssertEqual(segs[0].end, end)
    }

    func test_emptyScheduleReturnsNoSegments() {
        let tz = TimeZone(identifier: "UTC")!
        let start = d(2026, 6, 22, 1, 0, tz: tz)
        let end = d(2026, 6, 22, 5, 0, tz: tz)
        XCTAssertEqual(basalSegments(basal: [], windowStart: start, windowEnd: end, timeZone: tz), [])
    }
}
