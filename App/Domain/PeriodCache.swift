import Foundation

struct PeriodCache<Key: Hashable, Value> {
    private var entries: [Key: (value: Value, cachedAt: Date)] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func value(for key: Key, now: Date = Date(), newerThan: Date? = nil) -> Value? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.cachedAt) < ttl else { return nil }
        if let newerThan, entry.cachedAt < newerThan {
            return nil
        }
        return entry.value
    }

    mutating func store(_ value: Value, for key: Key, now: Date = Date()) {
        entries[key] = (value, now)
    }
}
