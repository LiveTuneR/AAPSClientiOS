import Foundation

final class WatchPayloadStore: @unchecked Sendable {
    static let appGroup = "group.com.nightaps.aapsclientios.watch"
    static let payloadUpdated = Notification.Name("aaps.watch.payloadUpdated")

    private let defaults: UserDefaults
    private let payloadKey = "watch.payload.v1"
    private let diagnosticKey = "watch.delivery.events.v1"
    private let lock = NSLock()

    init(defaults: UserDefaults? = UserDefaults(suiteName: WatchPayloadStore.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    @discardableResult
    func save(_ payload: WatchGlucosePayload) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let current = loadUnlocked(), current.sequence > payload.sequence { return false }
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        defaults.set(data, forKey: payloadKey)
        return true
    }

    func load() -> WatchGlucosePayload? {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    func record(_ state: String, sequence: Int64? = nil, details: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        var events = (defaults.array(forKey: diagnosticKey) as? [String]) ?? []
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(state) seq=\(sequence.map(String.init) ?? "-") \(details ?? "")"
        events.append(line)
        if events.count > 100 { events.removeFirst(events.count - 100) }
        defaults.set(events, forKey: diagnosticKey)
    }

    private func loadUnlocked() -> WatchGlucosePayload? {
        guard let data = defaults.data(forKey: payloadKey) else { return nil }
        return try? JSONDecoder().decode(WatchGlucosePayload.self, from: data)
    }
}
