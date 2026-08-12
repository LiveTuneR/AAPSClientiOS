import EventKit
import Foundation

@MainActor
final class CalendarGlucoseBridge: GlucoseSnapshotOutput {
    static let shared = CalendarGlucoseBridge()
    static let enabledKey = "calendarBridge.enabled"

    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private let calendarIdentifierKey = "calendarBridge.calendarIdentifier"
    private let eventIdentifierKey = "calendarBridge.eventIdentifier"
    private let lastSequenceKey = "calendarBridge.lastSequence"
    private let eventMarker = "AAPSClientiOS glucose bridge"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    var authorizationDescription: String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            if status == .fullAccess { return "Full access" }
            if status == .writeOnly { return "Write only" }
        }
        if status == .authorized { return "Full access" }
        if status == .denied { return "Denied" }
        if status == .restricted { return "Restricted" }
        if status == .notDetermined { return "Not requested" }
        return "Unknown"
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let authorized = await requestAuthorization()
            defaults.set(authorized, forKey: Self.enabledKey)
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: authorized ? "enabled" : "permission-denied"
            )
            return authorized
        }
        defaults.set(false, forKey: Self.enabledKey)
        removeCurrentEvent()
        DeliveryDiagnostics.shared.record(channel: "calendar", state: "disabled")
        return false
    }

    func publish(snapshot: GlucoseSnapshot, config: DisplayConfig, force: Bool) {
        guard Self.isEnabled else { return }
        let payload = WatchGlucosePayload(snapshot: snapshot, config: config)
        let lastSequence = Int64(defaults.double(forKey: lastSequenceKey))
        guard force || payload.sequence != lastSequence else { return }

        guard hasFullAccess else {
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "permission-missing", sequence: payload.sequence
            )
            return
        }
        guard let calendar = glucoseCalendar() else {
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "calendar-unavailable", sequence: payload.sequence
            )
            return
        }

        removeCurrentEvent()
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = calendarTitle(payload)
        event.notes = eventMarker
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(10 * 60)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            defaults.set(event.eventIdentifier, forKey: eventIdentifierKey)
            defaults.set(Double(payload.sequence), forKey: lastSequenceKey)
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "event-saved", sequence: payload.sequence
            )
        } catch {
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "save-failed", sequence: payload.sequence,
                details: error.localizedDescription
            )
        }
    }

    private var hasFullAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    private func requestAuthorization() async -> Bool {
        if hasFullAccess { return true }
        do {
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            }
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
        } catch {
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "permission-error", details: error.localizedDescription
            )
            return false
        }
    }

    private func glucoseCalendar() -> EKCalendar? {
        if let identifier = defaults.string(forKey: calendarIdentifierKey),
           let calendar = eventStore.calendar(withIdentifier: identifier) {
            return calendar
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "AAPS Glucose"
        calendar.source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
            ?? eventStore.sources.first
        guard calendar.source != nil else { return nil }
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            defaults.set(calendar.calendarIdentifier, forKey: calendarIdentifierKey)
            return calendar
        } catch {
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "calendar-create-failed",
                details: error.localizedDescription
            )
            return nil
        }
    }

    private func removeCurrentEvent() {
        guard let identifier = defaults.string(forKey: eventIdentifierKey),
              let event = eventStore.event(withIdentifier: identifier) else {
            defaults.removeObject(forKey: eventIdentifierKey)
            return
        }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            defaults.removeObject(forKey: eventIdentifierKey)
        } catch {
            DeliveryDiagnostics.shared.record(
                channel: "calendar", state: "remove-failed", details: error.localizedDescription
            )
        }
    }

    private func calendarTitle(_ payload: WatchGlucosePayload) -> String {
        let unit = payload.unitsRaw.lowercased().contains("mmol") ? "mmol/L" : "mg/dL"
        let delta = payload.formattedDelta()
        return [payload.formattedValue(), unit, payload.trendSymbol, delta]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
