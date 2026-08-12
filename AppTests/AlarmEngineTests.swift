import XCTest
@testable import AAPSClientiOS

final class AlarmEngineTests: XCTestCase {

    private let thresholds = AlarmThresholds(
        urgentLow: 55, low: 70, high: 180, urgentHigh: 250, staleMinutes: 15
    )

    func test_urgentLowFires() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 50, trend: .singleDown)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .urgentLow)
    }

    func test_lowFires() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 65, trend: .flat)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .low)
    }

    func test_highFires() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 200, trend: .flat)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .high)
    }

    func test_urgentHighFires() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 260, trend: .singleUp)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .urgentHigh)
    }

    func test_inRangeReturnsNil() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 120, trend: .flat)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertNil(result)
    }

    func test_noDataWhenStale() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 120, trend: .flat)
        let staleUpdate = Date().addingTimeInterval(-20 * 60)
        let result = engine.evaluate(latest: reading, lastUpdate: staleUpdate, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .noData)
    }

    func test_noDataWhenNilReading() {
        let engine = AlarmEngineLive()
        let result = engine.evaluate(latest: nil, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .noData)
    }

    func test_urgentOverridesNormal() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 50, trend: .doubleDown)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .urgentLow)
    }

    func test_snoozedTypeSuppressed() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 50, trend: .flat)
        let futureDate = Date().addingTimeInterval(600)
        engine.snooze(.urgentLow, until: futureDate)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertNil(result)
    }

    func test_snoozedExpiredFiresAgain() {
        let engine = AlarmEngineLive()
        let reading = GlucoseReading(date: .now, mgdl: 50, trend: .flat)
        let pastDate = Date().addingTimeInterval(-600)
        engine.snooze(.urgentLow, until: pastDate)
        let result = engine.evaluate(latest: reading, lastUpdate: .now, now: .now, thresholds: thresholds)
        XCTAssertEqual(result, .urgentLow)
    }

    func test_predictedLowFiresBelowThreshold() {
        let engine = AlarmEngineLive()
        let result = engine.evaluatePredictedLow(minPredBgMgdl: 60, thresholdMgdl: 70, now: .now)
        XCTAssertEqual(result, .predictedLow)
    }

    func test_predictedLowDoesNotFireAtOrAboveThreshold() {
        let engine = AlarmEngineLive()
        let result = engine.evaluatePredictedLow(minPredBgMgdl: 70, thresholdMgdl: 70, now: .now)
        XCTAssertNil(result)
    }

    func test_predictedLowNilWhenNoPrediction() {
        let engine = AlarmEngineLive()
        let result = engine.evaluatePredictedLow(minPredBgMgdl: nil, thresholdMgdl: 70, now: .now)
        XCTAssertNil(result)
    }

    func test_isSnoozedTrueBeforeExpiry() {
        let engine = AlarmEngineLive()
        engine.snooze(.low, until: Date().addingTimeInterval(900))
        XCTAssertTrue(engine.isSnoozed(.low, now: Date()))
    }

    func test_isSnoozedFalseAfterExpiry() {
        let engine = AlarmEngineLive()
        engine.snooze(.low, until: Date().addingTimeInterval(900))
        XCTAssertFalse(engine.isSnoozed(.low, now: Date().addingTimeInterval(901)))
    }

    func test_isSnoozedFalseWhenNeverSnoozed() {
        let engine = AlarmEngineLive()
        XCTAssertFalse(engine.isSnoozed(.urgentHigh, now: .now))
    }

    func test_predictedLowRespectsSnooze() {
        let engine = AlarmEngineLive()
        let futureDate = Date().addingTimeInterval(600)
        engine.snooze(.predictedLow, until: futureDate)
        let result = engine.evaluatePredictedLow(minPredBgMgdl: 50, thresholdMgdl: 70, now: .now)
        XCTAssertNil(result)
    }
}
