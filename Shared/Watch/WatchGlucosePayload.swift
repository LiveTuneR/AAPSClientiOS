import Foundation

struct WatchGlucoseSample: Codable, Equatable {
    let timestamp: Int64
    let mgdl: Int
}

struct WatchGlucosePayload: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let dataKey = "aaps.watch.payload"

    let schemaVersion: Int
    let sequence: Int64
    let generatedAt: Int64
    let readingTimestamp: Int64
    let mgdl: Int
    let trendRaw: String
    let delta: Int?
    let unitsRaw: String
    let urgentLow: Int
    let low: Int
    let high: Int
    let urgentHigh: Int
    let staleMinutes: Int
    let iob: Double?
    let cob: Double?
    let tempBasalRate: Double?
    let activeProfileName: String?
    let activeProfilePercentage: Int?
    let history: [WatchGlucoseSample]

    #if os(iOS)
    init(snapshot: GlucoseSnapshot, config: DisplayConfig, now: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        sequence = Int64(snapshot.date.timeIntervalSince1970 * 1_000)
        generatedAt = Int64(now.timeIntervalSince1970 * 1_000)
        readingTimestamp = Int64(snapshot.date.timeIntervalSince1970 * 1_000)
        mgdl = snapshot.mgdl
        trendRaw = snapshot.trend.rawValue
        delta = snapshot.delta
        unitsRaw = config.units.rawValue
        urgentLow = config.thresholds.urgentLow
        low = config.thresholds.low
        high = config.thresholds.high
        urgentHigh = config.thresholds.urgentHigh
        staleMinutes = config.thresholds.staleMinutes
        iob = snapshot.iob
        cob = snapshot.cob
        tempBasalRate = snapshot.tempBasalRate
        activeProfileName = snapshot.activeProfileName
        activeProfilePercentage = snapshot.activeProfilePercentage
        history = snapshot.history.map {
            WatchGlucoseSample(timestamp: Int64($0.date.timeIntervalSince1970 * 1_000), mgdl: $0.mgdl)
        }
    }
    #endif

    var readingDate: Date { Date(timeIntervalSince1970: Double(readingTimestamp) / 1_000) }
    var generatedDate: Date { Date(timeIntervalSince1970: Double(generatedAt) / 1_000) }

    func isStale(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(readingDate) >= Double(staleMinutes * 60)
    }

    func formattedValue() -> String {
        if unitsRaw.lowercased().contains("mmol") {
            return String(format: "%.1f", Double(mgdl) / 18.0)
        }
        return String(mgdl)
    }

    func formattedDelta() -> String {
        guard let delta else { return "" }
        let prefix = delta > 0 ? "+" : ""
        if unitsRaw.lowercased().contains("mmol") {
            return prefix + String(format: "%.1f", Double(delta) / 18.0)
        }
        return prefix + String(delta)
    }

    var trendSymbol: String {
        switch trendRaw.lowercased() {
        case "doubleup": return "↑↑"
        case "singleup": return "↑"
        case "fortyfiveup": return "↗"
        case "flat": return "→"
        case "fortyfivedown": return "↘"
        case "singledown": return "↓"
        case "doubledown": return "↓↓"
        default: return "·"
        }
    }
}

struct WatchDeliveryAck: Codable, Equatable {
    static let dataKey = "aaps.watch.ack"
    let sequence: Int64
    let receivedAt: Int64
}
