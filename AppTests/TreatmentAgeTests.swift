import XCTest
@testable import AAPSClientiOS

final class TreatmentAgeTests: XCTestCase {

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
}
