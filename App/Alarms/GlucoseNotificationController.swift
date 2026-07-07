import Foundation
import UserNotifications

struct GlucoseNotificationContent: Equatable {
    let title: String
    let body: String
}

protocol GlucoseNotificationPublishing {
    func replace(with content: GlucoseNotificationContent)
    func remove()
}

final class GlucoseNotificationController: GlucoseNotificationPublishing {
    static let identifier = "glucose.latest"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func replace(with content: GlucoseNotificationContent) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])

        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.threadIdentifier = Self.identifier
        notification.interruptionLevel = .passive

        center.add(UNNotificationRequest(
            identifier: Self.identifier,
            content: notification,
            trigger: nil
        ))
    }

    func remove() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    static func content(
        latest: GlucoseReading,
        previous: GlucoseReading?,
        units: GlucoseUnits,
        timeText: String
    ) -> GlucoseNotificationContent {
        let value = Formatting.format(latest.mgdl, units: units)
        let trend = Formatting.trendSymbol(latest.trend)
        let unit = units.rawValue
        let deltaText: String
        if let previous {
            let delta = latest.mgdl - previous.mgdl
            let formatted = Formatting.format(abs(delta), units: units)
            deltaText = " \(delta >= 0 ? "+" : "-")\(formatted)"
        } else {
            deltaText = ""
        }

        return GlucoseNotificationContent(
            title: "\(value) \(trend)\(deltaText) \(unit)",
            body: String(
                format: String(localized: "notification.glucose_measured"),
                timeText
            )
        )
    }
}

final class DummyGlucoseNotificationPublisher: GlucoseNotificationPublishing {
    func replace(with content: GlucoseNotificationContent) {}
    func remove() {}
}
