import Foundation

/// When the next background poll is due.
///
/// The CGM produces a value roughly every five minutes, so polling on a blind
/// 60 s interval wastes about four radio wake-ups out of five.
enum BackgroundPollSchedule {
    static let cgmCadence: TimeInterval = 5 * 60
    static let postReadingOffset: TimeInterval = 20
    static let retryInterval: TimeInterval = 30
    static let missCap = 4
    static let fallbackInterval: TimeInterval = 5 * 60
    static let aggressiveInterval: TimeInterval = 60

    static func nextPollDate(
        lastReadingDate: Date?,
        consecutiveMisses: Int,
        now: Date
    ) -> Date {
        guard let lastReadingDate, consecutiveMisses < missCap else {
            return now.addingTimeInterval(fallbackInterval)
        }
        if consecutiveMisses > 0 {
            return now.addingTimeInterval(retryInterval)
        }
        let expected = lastReadingDate.addingTimeInterval(cgmCadence + postReadingOffset)
        return max(expected, now)
    }
}
