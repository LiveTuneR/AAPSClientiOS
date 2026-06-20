import Foundation

enum Formatting {
    static func classify(mgdl: Int, thresholds: AlarmThresholds) -> GlucoseClassification {
        if mgdl <= thresholds.urgentLow { return .urgentLow }
        if mgdl <= thresholds.low { return .low }
        if mgdl >= thresholds.urgentHigh { return .urgentHigh }
        if mgdl > thresholds.high { return .high }
        return .inRange
    }

    static func format(_ mgdl: Int, units: GlucoseUnits) -> String {
        switch units {
        case .mgdl: return "\(mgdl)"
        case .mmol: return String(format: "%.1f", Double(mgdl) / 18.0182)
        }
    }

    static func trendSymbol(_ trend: TrendArrow) -> String {
        switch trend {
        case .doubleUp: return "⇈"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "⇊"
        case .none: return "?"
        }
    }
}
