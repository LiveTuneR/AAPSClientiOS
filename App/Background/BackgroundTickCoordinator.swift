import Foundation
import UIKit

/// Owns the background poll cadence and keeps each refresh alive across an
/// audio-session drop.
@MainActor final class BackgroundTickCoordinator {
    private var consecutiveMisses = 0
    private var lastSeenReadingDate: Date?

    func nextDelay(mode: KeepAliveMode, lastReadingDate: Date?) -> TimeInterval {
        if mode == .aggressive {
            return BackgroundPollSchedule.aggressiveInterval
        }
        let next = BackgroundPollSchedule.nextPollDate(
            lastReadingDate: lastReadingDate,
            consecutiveMisses: consecutiveMisses,
            now: Date()
        )
        return max(1, next.timeIntervalSinceNow)
    }

    func tick(store: AppStore) async {
        let application = UIApplication.shared
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = application.beginBackgroundTask(withName: "ns-background-refresh") {
            if taskId != .invalid {
                application.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        try? await store.refresh(scope: .light)
        recordOutcome(latestReadingDate: store.readings.first?.date)

        if taskId != .invalid {
            application.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }

    private func recordOutcome(latestReadingDate: Date?) {
        guard let latestReadingDate else {
            consecutiveMisses += 1
            return
        }
        if latestReadingDate == lastSeenReadingDate {
            consecutiveMisses += 1
        } else {
            consecutiveMisses = 0
            lastSeenReadingDate = latestReadingDate
        }
    }

    func resetMisses() {
        consecutiveMisses = 0
    }
}
