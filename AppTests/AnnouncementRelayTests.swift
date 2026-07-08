import XCTest
@testable import AAPSClientiOS

final class AnnouncementRelayTests: XCTestCase {

    private func announcement(id: String, minutesAgo: Double, notes: String? = "Pump alert") -> Treatment {
        Treatment(
            id: id, eventType: "Announcement", date: Date().addingTimeInterval(-minutesAgo * 60),
            insulin: nil, carbs: nil, durationMin: nil, enteredBy: nil, notes: notes,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )
    }

    func test_returnsNil_whenNoAnnouncements() {
        let result = AnnouncementRelay.pendingAnnouncement(in: [], lastNotifiedDate: nil)
        XCTAssertNil(result)
    }

    func test_returnsLatest_whenFreshAndNotYetNotified() {
        let old = announcement(id: "a1", minutesAgo: 90)
        let fresh = announcement(id: "a2", minutesAgo: 5)
        let result = AnnouncementRelay.pendingAnnouncement(in: [old, fresh], lastNotifiedDate: nil)
        XCTAssertEqual(result?.id, "a2")
    }

    func test_returnsNil_whenOlderThanValidityWindow() {
        let stale = announcement(id: "a1", minutesAgo: 61)
        let result = AnnouncementRelay.pendingAnnouncement(in: [stale], lastNotifiedDate: nil)
        XCTAssertNil(result)
    }

    func test_returnsNil_whenAlreadyNotified() {
        let a = announcement(id: "a1", minutesAgo: 5)
        let result = AnnouncementRelay.pendingAnnouncement(in: [a], lastNotifiedDate: a.date)
        XCTAssertNil(result)
    }

    func test_ignoresNonAnnouncementEventTypes() {
        let carbs = Treatment(
            id: "c1", eventType: "Carb Correction", date: Date(),
            insulin: nil, carbs: 20, durationMin: nil, enteredBy: nil, notes: nil,
            targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
            absolute: nil, tempBasalPercent: nil
        )
        let result = AnnouncementRelay.pendingAnnouncement(in: [carbs], lastNotifiedDate: nil)
        XCTAssertNil(result)
    }
}
