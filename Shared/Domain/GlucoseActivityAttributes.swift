import ActivityKit
import Foundation

struct GlucoseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let mgdl: Int
        let trendRaw: String       // TrendArrow.rawValue
        let delta: Int?
        let date: Date
        let iob: Double?
        let unitsRaw: String       // GlucoseUnits.rawValue
    }
    var title: String = "Glucose"
}
