import XCTest
@testable import AAPSClientiOS

final class IapsAnnouncementMappingTests: XCTestCase {
    func test_closedLoopMapsToLoopingTrue() {
        XCTAssertEqual(IapsAnnouncementMapping.notes(forMode: "CLOSED_LOOP"), "looping:true")
    }

    func test_openLoopMapsToLoopingFalse() {
        XCTAssertEqual(IapsAnnouncementMapping.notes(forMode: "OPEN_LOOP"), "looping:false")
    }

    func test_suspendedByUserMapsToPumpSuspend() {
        XCTAssertEqual(IapsAnnouncementMapping.notes(forMode: "SUSPENDED_BY_USER"), "pump:suspend")
    }

    func test_disconnectedPumpMapsToPumpSuspend() {
        // iAPS has no separate "disconnect" concept — pump:suspend is the closest match, and it's
        // indefinite (no duration argument exists on iAPS's side for pump commands).
        XCTAssertEqual(IapsAnnouncementMapping.notes(forMode: "DISCONNECTED_PUMP"), "pump:suspend")
    }

    func test_unknownModeReturnsNil() {
        XCTAssertNil(IapsAnnouncementMapping.notes(forMode: "SOMETHING_ELSE"))
    }
}
