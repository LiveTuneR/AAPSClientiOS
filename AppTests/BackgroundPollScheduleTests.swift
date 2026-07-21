import XCTest
@testable import AAPSClientiOS

final class BackgroundPollScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    func test_alignsToCgmCadence_whenLastReadingIsRecent() {
        let lastReading = now.addingTimeInterval(-60)

        let next = BackgroundPollSchedule.nextPollDate(
            lastReadingDate: lastReading,
            consecutiveMisses: 0,
            now: now
        )

        XCTAssertEqual(next.timeIntervalSince(now), 4 * 60 + 20, accuracy: 0.001)
    }

    func test_pollsImmediately_whenScheduleIsAlreadyInThePast() {
        let lastReading = now.addingTimeInterval(-3600)

        let next = BackgroundPollSchedule.nextPollDate(
            lastReadingDate: lastReading,
            consecutiveMisses: 0,
            now: now
        )

        XCTAssertEqual(next, now)
    }

    func test_usesShortRetry_afterAMissedReading() {
        let next = BackgroundPollSchedule.nextPollDate(
            lastReadingDate: now.addingTimeInterval(-60),
            consecutiveMisses: 1,
            now: now
        )

        XCTAssertEqual(next.timeIntervalSince(now), 30, accuracy: 0.001)
    }

    func test_fallsBackToFixedInterval_afterMissCap() {
        let next = BackgroundPollSchedule.nextPollDate(
            lastReadingDate: now.addingTimeInterval(-60),
            consecutiveMisses: 4,
            now: now
        )

        XCTAssertEqual(next.timeIntervalSince(now), 5 * 60, accuracy: 0.001)
    }

    func test_fallsBackToFixedInterval_whenThereAreNoReadings() {
        let next = BackgroundPollSchedule.nextPollDate(
            lastReadingDate: nil,
            consecutiveMisses: 0,
            now: now
        )

        XCTAssertEqual(next.timeIntervalSince(now), 5 * 60, accuracy: 0.001)
    }

    func test_aggressiveModeUsesFixedShortInterval() {
        XCTAssertEqual(BackgroundPollSchedule.aggressiveInterval, 60)
    }
}
