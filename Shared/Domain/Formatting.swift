import Foundation
import SwiftUI

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
        case .mmol: return String(format: "%.1f", Double(mgdl) / glucoseMmolFactor)
        }
    }

    static func format(_ mgdl: Double, units: GlucoseUnits) -> String {
        switch units {
        case .mgdl: return String(format: "%.0f", mgdl)
        case .mmol: return String(format: "%.1f", mgdl / glucoseMmolFactor)
        }
    }

    /// Renders a low–high target range, collapsing to a single value when they match.
    static func targetRangeText(lo: Int, hi: Int, units: GlucoseUnits) -> String {
        let suffix = units == .mmol ? "mmol/l" : "mg/dl"
        return lo == hi
            ? "\(format(lo, units: units)) \(suffix)"
            : "\(format(lo, units: units))–\(format(hi, units: units)) \(suffix)"
    }

    static func color(for classification: GlucoseClassification) -> Color {
        switch classification {
        case .urgentLow, .urgentHigh: return .red
        case .low, .high: return .yellow
        case .inRange: return .green
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
