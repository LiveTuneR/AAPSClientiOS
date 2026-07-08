import XCTest
@testable import AAPSClientiOS

final class StatisticsTests: XCTestCase {

    private let thresholds = AlarmThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250, staleMinutes: 15)

    func test_emptyReturnsZeros() {
        let s = StatisticsCompute.stats(readings: [], thresholds: thresholds)
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.averageMgdl, 0)
    }

    func test_singleValue() {
        let readings = [GlucoseReading]()
        let s = StatisticsCompute.stats(readings: readings, thresholds: thresholds)
        XCTAssertEqual(s.count, 0)
    }

    func test_allInRange() {
        let now = Date()
        let readings: [GlucoseReading] = (0..<10).map { i in
            GlucoseReading(date: now.addingTimeInterval(Double(-i) * 300), mgdl: 120, trend: .flat)
        }
        let s = StatisticsCompute.stats(readings: readings, thresholds: thresholds)
        XCTAssertEqual(s.count, 10)
        XCTAssertEqual(s.averageMgdl, 120)
        XCTAssertEqual(s.tirInRange, 100)
        XCTAssertEqual(s.tirBelow, 0)
    }

    func test_mixedRange() {
        let now = Date()
        let readings: [GlucoseReading] = [
            GlucoseReading(date: now, mgdl: 50, trend: .flat),
            GlucoseReading(date: now.addingTimeInterval(-300), mgdl: 65, trend: .flat),
            GlucoseReading(date: now.addingTimeInterval(-600), mgdl: 120, trend: .flat),
            GlucoseReading(date: now.addingTimeInterval(-900), mgdl: 200, trend: .flat),
        ]
        let s = StatisticsCompute.stats(readings: readings, thresholds: thresholds)
        XCTAssertEqual(s.tirBelowUrgent, 25)
        XCTAssertEqual(s.tirBelow, 25)
        XCTAssertEqual(s.tirInRange, 25)
        XCTAssertEqual(s.tirAbove, 25)
        XCTAssertTrue(s.sdMgdl > 0)
        XCTAssertTrue(s.gmiPercent > 0)
    }

    func test_dailyDoses_splitsBasalAndBolus() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = cal.startOfDay(for: Date())
        let windowEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let basal = [BasalEntry(startSeconds: 0, rate: 1.0)] // flat 1 U/h all day
        let bolus = Treatment(
            id: "b1", eventType: "Meal Bolus", date: dayStart.addingTimeInterval(3600),
            insulin: 5, carbs: nil, durationMin: nil, enteredBy: nil, notes: nil,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )

        let doses = StatisticsCompute.dailyDoses(
            treatments: [bolus], basal: basal, windowStart: dayStart, windowEnd: windowEnd, timeZone: cal.timeZone
        )

        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(doses[0].basalUnits, 24.0, accuracy: 0.01)
        XCTAssertEqual(doses[0].bolusUnits, 5)
        XCTAssertEqual(doses[0].totalUnits, 29.0, accuracy: 0.01)
    }

    func test_dailyDoses_respectsTempBasalOverride() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = cal.startOfDay(for: Date())
        let windowEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let basal = [BasalEntry(startSeconds: 0, rate: 1.0)]
        // Zero-temp for the first 2 hours of the day.
        let tempBasal = Treatment(
            id: "t1", eventType: "Temp Basal", date: dayStart,
            insulin: nil, carbs: nil, durationMin: 120, enteredBy: nil, notes: nil,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: 0, tempBasalPercent: nil
        )

        let doses = StatisticsCompute.dailyDoses(
            treatments: [tempBasal], basal: basal, windowStart: dayStart, windowEnd: windowEnd, timeZone: cal.timeZone
        )

        // 22h at 1.0 U/h + 2h at 0 U/h = 22.0
        XCTAssertEqual(doses[0].basalUnits, 22.0, accuracy: 0.01)
    }
}
