import Foundation

struct DeliveryDiagnosticEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let channel: String
    let state: String
    let sequence: Int64?
    let details: String?
}

final class DeliveryDiagnostics: @unchecked Sendable {
    static let shared = DeliveryDiagnostics()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "delivery.diagnostics.events.v1"
    private let limit = 250

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(channel: String, state: String, sequence: Int64? = nil, details: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        var events = loadUnlocked()
        events.append(DeliveryDiagnosticEvent(
            id: UUID(), date: Date(), channel: channel, state: state,
            sequence: sequence, details: details
        ))
        if events.count > limit { events.removeFirst(events.count - limit) }
        if let data = try? JSONEncoder().encode(events) { defaults.set(data, forKey: key) }
    }

    func events() -> [DeliveryDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    func clear() {
        lock.lock()
        defaults.removeObject(forKey: key)
        lock.unlock()
    }

    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return events().map { event in
            let sequence = event.sequence.map { " seq=\($0)" } ?? ""
            let details = event.details.map { " \($0)" } ?? ""
            return "\(formatter.string(from: event.date)) [\(event.channel)] \(event.state)\(sequence)\(details)"
        }.joined(separator: "\n")
    }

    private func loadUnlocked() -> [DeliveryDiagnosticEvent] {
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([DeliveryDiagnosticEvent].self, from: data)
        else { return [] }
        return events
    }
}
