import XCTest
@testable import AAPSClientiOS

final class TreatmentAgeTests: XCTestCase {
    func test_activeTempTarget_cancelEventSuppressesEarlierTarget() {
        let now = Date()
        let active = Treatment(
            id: "active", eventType: "Temporary Target", date: now.addingTimeInterval(-300),
            insulin: nil, carbs: nil, durationMin: 60, enteredBy: nil, notes: nil,
            targetBottom: 90, targetTop: 90, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )
        let cancellation = Treatment(
            id: "cancel", eventType: "Temporary Target", date: now.addingTimeInterval(-60),
            insulin: nil, carbs: nil, durationMin: 0, enteredBy: nil, notes: nil,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )

        XCTAssertNil(Treatment.activeTempTarget(in: [active, cancellation], now: now))
    }

    func test_activeTempTarget_findsLatestUnexpiredTarget() {
        let now = Date()
        let target = Treatment(
            id: "active", eventType: "Temporary Target", date: now.addingTimeInterval(-300),
            insulin: nil, carbs: nil, durationMin: 60, enteredBy: nil, notes: nil,
            targetBottom: 90, targetTop: 90, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )

        XCTAssertEqual(Treatment.activeTempTarget(in: [target], now: now), target)
    }

    func test_lastEventAgeReturnsNilForEmpty() {
        let result = TreatmentAgeCalc.lastEventAge(treatments: [], eventTypes: ["Site Change"], now: Date())
        XCTAssertNil(result)
    }

    func test_lastEventAgeFindsLatest() {
        let now = Date()
        let treatments: [Treatment] = [
            Treatment(id: "1", eventType: "Site Change", date: now.addingTimeInterval(-3600), insulin: nil, carbs: nil, durationMin: nil, enteredBy: nil, notes: nil, targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil, absolute: nil, tempBasalPercent: nil),
            Treatment(id: "2", eventType: "Site Change", date: now.addingTimeInterval(-7200), insulin: nil, carbs: nil, durationMin: nil, enteredBy: nil, notes: nil, targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil, absolute: nil, tempBasalPercent: nil),
        ]
        let age = TreatmentAgeCalc.lastEventAge(treatments: treatments, eventTypes: ["Site Change"], now: now)
        XCTAssertEqual(age, 3600)
    }

    func test_formatAge() {
        XCTAssertEqual(TreatmentAgeCalc.formatAge(3600), "1h")
        XCTAssertEqual(TreatmentAgeCalc.formatAge(90000), "1d 1h")
        XCTAssertEqual(TreatmentAgeCalc.formatAge(7200), "2h")
        XCTAssertEqual(TreatmentAgeCalc.formatAge(nil), "—")
    }

    func test_mergedHistoryWindow_dedupsSortsAndTrims() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = Treatment(
            id: "stale", eventType: "Site Change", date: now.addingTimeInterval(-8 * 86_400),
            insulin: nil, carbs: nil, durationMin: nil, enteredBy: nil, notes: nil,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )
        let older = Treatment(
            id: "same", eventType: "Meal Bolus", date: now.addingTimeInterval(-3_600),
            insulin: 1, carbs: 10, durationMin: nil, enteredBy: nil, notes: nil,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )
        let newer = Treatment(
            id: "same", eventType: "Meal Bolus", date: now.addingTimeInterval(-1_800),
            insulin: 2, carbs: 20, durationMin: nil, enteredBy: nil, notes: "new",
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )
        let latest = Treatment(
            id: "latest", eventType: "Temporary Target", date: now.addingTimeInterval(-600),
            insulin: nil, carbs: nil, durationMin: 60, enteredBy: nil, notes: nil,
            targetBottom: 90, targetTop: 90, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )

        let merged = Treatment.mergedHistoryWindow(
            existing: [stale, older],
            incoming: [newer, latest],
            now: now,
            days: 7
        )

        XCTAssertEqual(merged.map(\.id), ["latest", "same"])
        XCTAssertEqual(merged.first?.date, latest.date)
        XCTAssertEqual(merged.last?.carbs, 20)
        XCTAssertEqual(merged.count, 2)
    }

    func test_levelIsOkBelowWarnThreshold() {
        let level = ConsumableAgeCalc.level(ageSeconds: 10 * 3600, warnHours: 48, criticalHours: 72)
        XCTAssertEqual(level, .ok)
    }

    func test_levelIsWarnAtWarnThreshold() {
        let level = ConsumableAgeCalc.level(ageSeconds: 48 * 3600, warnHours: 48, criticalHours: 72)
        XCTAssertEqual(level, .warn)
    }

    func test_levelIsCriticalAtCriticalThreshold() {
        let level = ConsumableAgeCalc.level(ageSeconds: 72 * 3600, warnHours: 48, criticalHours: 72)
        XCTAssertEqual(level, .critical)
    }

    func test_levelIsOkWhenAgeUnknown() {
        let level = ConsumableAgeCalc.level(ageSeconds: nil, warnHours: 48, criticalHours: 72)
        XCTAssertEqual(level, .ok)
    }
}
