import XCTest
@testable import AAPSClientiOS

final class ActualBasalSegmentsTests: XCTestCase {

    private func tb(_ id: String, date: Date, durationMin: Int, absolute: Double? = nil, percent: Int? = nil) -> Treatment {
        Treatment(id: id, eventType: "Temp Basal", date: date, insulin: nil, carbs: nil,
                  durationMin: durationMin, enteredBy: nil, notes: nil, targetBottom: nil,
                  targetTop: nil, profileName: nil, percentage: nil, absolute: absolute, tempBasalPercent: percent)
    }

    func test_noTempBasalReturnsScheduledUnchanged() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(3600)
        let scheduled = [BasalSegment(start: start, end: end, rate: 0.8)]
        let segs = actualBasalSegments(scheduled: scheduled, tempBasal: [], windowStart: start, windowEnd: end)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].rate, 0.8)
        XCTAssertFalse(segs[0].isTemp)
    }

    func test_zeroTempOverridesScheduledForDuration() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(3600)
        let scheduled = [BasalSegment(start: start, end: end, rate: 1.0)]
        let temp = [tb("zt", date: start.addingTimeInterval(600), durationMin: 30, absolute: 0.0)]
        let segs = actualBasalSegments(scheduled: scheduled, tempBasal: temp, windowStart: start, windowEnd: end)
            .sorted { $0.start < $1.start }
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0].rate, 1.0); XCTAssertFalse(segs[0].isTemp)
        XCTAssertEqual(segs[1].rate, 0.0); XCTAssertTrue(segs[1].isTemp)
        XCTAssertEqual(segs[1].start, start.addingTimeInterval(600))
        XCTAssertEqual(segs[1].end, start.addingTimeInterval(600 + 1800))
        XCTAssertEqual(segs[2].rate, 1.0); XCTAssertFalse(segs[2].isTemp)
    }

    func test_percentTempBasalResolvesAgainstScheduledRateAtThatTime() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(3600)
        let scheduled = [BasalSegment(start: start, end: end, rate: 1.0)]
        let temp = [tb("pct", date: start.addingTimeInterval(600), durationMin: 30, percent: 150)]
        let segs = actualBasalSegments(scheduled: scheduled, tempBasal: temp, windowStart: start, windowEnd: end)
            .sorted { $0.start < $1.start }
        XCTAssertEqual(segs[1].rate, 1.5, accuracy: 0.001)
        XCTAssertTrue(segs[1].isTemp)
    }

    func test_newTempBasalCancelsEarlierStillRunningOne() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(3600)
        let scheduled = [BasalSegment(start: start, end: end, rate: 1.0)]
        let temp = [
            tb("first", date: start.addingTimeInterval(0), durationMin: 60, absolute: 0.0),
            tb("second", date: start.addingTimeInterval(600), durationMin: 30, absolute: 2.0),
        ]
        let segs = actualBasalSegments(scheduled: scheduled, tempBasal: temp, windowStart: start, windowEnd: end)
            .sorted { $0.start < $1.start }
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0].rate, 0.0); XCTAssertEqual(segs[0].end, start.addingTimeInterval(600))
        XCTAssertEqual(segs[1].rate, 2.0); XCTAssertEqual(segs[1].end, start.addingTimeInterval(600 + 1800))
        XCTAssertEqual(segs[2].rate, 1.0)
    }

    func test_durationZeroTreatmentCancelsWithoutAddingItsOwnSegment() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(3600)
        let scheduled = [BasalSegment(start: start, end: end, rate: 1.0)]
        let temp = [
            tb("running", date: start.addingTimeInterval(0), durationMin: 60, absolute: 0.0),
            tb("cancel", date: start.addingTimeInterval(600), durationMin: 0),
        ]
        let segs = actualBasalSegments(scheduled: scheduled, tempBasal: temp, windowStart: start, windowEnd: end)
            .sorted { $0.start < $1.start }
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].rate, 0.0); XCTAssertEqual(segs[0].end, start.addingTimeInterval(600))
        XCTAssertEqual(segs[1].rate, 1.0); XCTAssertEqual(segs[1].start, start.addingTimeInterval(600))
    }

    func test_tempBasalOutsideWindowIsIgnored() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(3600)
        let scheduled = [BasalSegment(start: start, end: end, rate: 1.0)]
        let temp = [tb("old", date: start.addingTimeInterval(-7200), durationMin: 30, absolute: 0.0)]
        let segs = actualBasalSegments(scheduled: scheduled, tempBasal: temp, windowStart: start, windowEnd: end)
        XCTAssertEqual(segs.count, 1)
        XCTAssertFalse(segs[0].isTemp)
    }
}
