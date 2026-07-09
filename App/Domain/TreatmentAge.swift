import Foundation

enum TreatmentAgeCalc {
    static func lastEventAge(treatments: [Treatment], eventTypes: [String], now: Date) -> TimeInterval? {
        let latest = treatments
            .filter { eventTypes.contains($0.eventType) }
            .max(by: { $0.date < $1.date })
        guard let t = latest else { return nil }
        return now.timeIntervalSince(t.date)
    }

    static func formatAge(_ seconds: TimeInterval?) -> String {
        guard let s = seconds else { return "—" }
        let days = Int(s) / 86400
        let hours = (Int(s) % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h"
    }
}

enum ConsumableLevel: Equatable {
    case ok, warn, critical
}

enum ConsumableAgeCalc {
    static func level(ageSeconds: TimeInterval?, warnHours: Int, criticalHours: Int) -> ConsumableLevel {
        guard let ageSeconds else { return .ok }
        let ageHours = ageSeconds / 3600
        if ageHours >= Double(criticalHours) { return .critical }
        if ageHours >= Double(warnHours) { return .warn }
        return .ok
    }
}
