import Foundation

protocol AlarmEngine {
    func evaluate(latest: GlucoseReading?, lastUpdate: Date, now: Date, thresholds: AlarmThresholds) -> AlarmType?
    func schedule(_ type: AlarmType)
    func snooze(_ type: AlarmType, until: Date)
}

final class AlarmEngineLive: AlarmEngine {
    private var snoozed: [AlarmType: Date] = [:]
    private let lock = NSLock()
    private let notifier: Notifier

    init(notifier: Notifier = DummyNotifier()) {
        self.notifier = notifier
    }

    func evaluate(latest: GlucoseReading?, lastUpdate: Date, now: Date, thresholds: AlarmThresholds) -> AlarmType? {
        if latest == nil {
            return nonSnoozed(.noData, now: now)
        }

        let staleSeconds = now.timeIntervalSince(lastUpdate)
        if staleSeconds > Double(thresholds.staleMinutes * 60) {
            return nonSnoozed(.noData, now: now)
        }

        guard let reading = latest else {
            return nonSnoozed(.noData, now: now)
        }

        let alarms: [AlarmType] = [
            reading.mgdl <= thresholds.urgentLow ? .urgentLow : nil,
            reading.mgdl > thresholds.urgentLow && reading.mgdl <= thresholds.low ? .low : nil,
            reading.mgdl >= thresholds.urgentHigh ? .urgentHigh : nil,
            reading.mgdl > thresholds.high && reading.mgdl < thresholds.urgentHigh ? .high : nil,
        ].compactMap { $0 }

        return alarms.first.map { nonSnoozed($0, now: now) } ?? nil
    }

    func schedule(_ type: AlarmType) {
        notifier.post(title: type.title, body: type.body, identifier: type.identifier)
    }

    func snooze(_ type: AlarmType, until: Date) {
        lock.lock()
        snoozed[type] = until
        lock.unlock()
        notifier.remove(identifier: type.identifier)
    }

    private func nonSnoozed(_ type: AlarmType, now: Date) -> AlarmType? {
        lock.lock()
        let until = snoozed[type]
        lock.unlock()
        if let until, now < until {
            return nil
        }
        return type
    }
}

extension AlarmType {
    var title: String {
        switch self {
        case .urgentLow: return "Urgent Low"
        case .low: return "Low Glucose"
        case .high: return "High Glucose"
        case .urgentHigh: return "Urgent High"
        case .noData: return "No Data"
        case .connectionLost: return "Connection Lost"
        }
    }

    var body: String {
        switch self {
        case .urgentLow: return "Glucose is critically low"
        case .low: return "Glucose is below target"
        case .high: return "Glucose is above target"
        case .urgentHigh: return "Glucose is critically high"
        case .noData: return "Glucose data is stale or missing"
        case .connectionLost: return "Cannot reach Nightscout"
        }
    }

    var identifier: String {
        switch self {
        case .urgentLow: return "alarm.urgentLow"
        case .low: return "alarm.low"
        case .high: return "alarm.high"
        case .urgentHigh: return "alarm.urgentHigh"
        case .noData: return "alarm.noData"
        case .connectionLost: return "alarm.connectionLost"
        }
    }
}

private final class DummyNotifier: Notifier {
    func post(title: String, body: String, identifier: String) {}
    func remove(identifier: String) {}
}
