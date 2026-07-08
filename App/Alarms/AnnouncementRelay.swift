import Foundation

/// Mirrors AndroidAPS's `NsClientNotificationsFromAnnouncements` relay
/// (`NsIncomingDataProcessor.kt`): a Nightscout "Announcement" therapy event is only
/// worth surfacing locally for 60 minutes after it was created, and only once.
enum AnnouncementRelay {
    static let validityWindow: TimeInterval = 60 * 60

    static func pendingAnnouncement(
        in treatments: [Treatment],
        lastNotifiedDate: Date?,
        now: Date = Date()
    ) -> Treatment? {
        guard let latest = treatments
            .filter({ $0.eventType == "Announcement" })
            .max(by: { $0.date < $1.date }),
              latest.date.addingTimeInterval(validityWindow) > now,
              latest.date != lastNotifiedDate else {
            return nil
        }
        return latest
    }
}
