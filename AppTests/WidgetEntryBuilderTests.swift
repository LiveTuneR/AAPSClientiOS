import XCTest
@testable import AAPSClientiOS

final class WidgetEntryBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_600)
    private func reading(_ mgdl: Int, agoSec: TimeInterval, trend: TrendArrow = .flat) -> GlucoseReading {
        GlucoseReading(date: now.addingTimeInterval(-agoSec), mgdl: mgdl, trend: trend)
    }

    func test_buildsDeltaFromTwoReadings() {
        let entry = WidgetEntryBuilder.build(
            readings: [reading(120, agoSec: 60, trend: .flat), reading(112, agoSec: 360)],
            loop: nil, config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertEqual(entry.mgdl, 120)
        XCTAssertEqual(entry.delta, 8)
        XCTAssertEqual(entry.minutesAgo, 1)
        XCTAssertFalse(entry.isStale)
        XCTAssertEqual(entry.state, .data)
    }

    func test_nilDeltaWithSingleReading() {
        let entry = WidgetEntryBuilder.build(
            readings: [reading(120, agoSec: 60)],
            loop: nil, config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertNil(entry.delta)
    }

    func test_staleWhenOlderThanThreshold() {
        let entry = WidgetEntryBuilder.build(
            readings: [reading(120, agoSec: 20 * 60)],
            loop: nil, config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertTrue(entry.isStale)
    }

    func test_emptyReadingsProducesNoDataState() {
        let entry = WidgetEntryBuilder.build(
            readings: [], loop: nil,
            config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertEqual(entry.state, .noData)
    }

    func test_carriesIobCobFromLoop() {
        let loop = LoopStatus(
            iob: 1.5, cob: 22, eventualBgMgdl: nil, tempBasalRate: nil,
            suggestedReason: nil, timestamp: now, predictions: nil,
            pumpBattery: nil, pumpReservoir: nil, uploaderBattery: nil, reason: nil
        )
        let entry = WidgetEntryBuilder.build(
            readings: [reading(120, agoSec: 60)],
            loop: loop, config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertEqual(entry.iob, 1.5)
        XCTAssertEqual(entry.cob, 22)
    }

    func test_carriesTempBasalRateFromLoop() {
        let loop = LoopStatus(
            iob: 1.5, cob: 22, eventualBgMgdl: nil, tempBasalRate: 0.85,
            suggestedReason: nil, timestamp: now, predictions: nil,
            pumpBattery: nil, pumpReservoir: nil, uploaderBattery: nil, reason: nil
        )
        let entry = WidgetEntryBuilder.build(
            readings: [reading(120, agoSec: 60)],
            loop: loop, config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertEqual(entry.tempBasalRate, 0.85)
    }

    func test_classificationUsesThresholds() {
        let entry = WidgetEntryBuilder.build(
            readings: [reading(60, agoSec: 60)],
            loop: nil, config: DisplayConfig(units: .mgdl, thresholds: .defaults), now: now
        )
        XCTAssertEqual(entry.classification, .low)
    }
}
