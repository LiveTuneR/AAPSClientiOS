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
        let cob: Double?
        let tempBasalRate: Double?
        let activeProfileName: String?
        let activeProfilePercentage: Int?

        init(
            mgdl: Int, trendRaw: String, delta: Int?, date: Date,
            iob: Double?, unitsRaw: String, cob: Double? = nil,
            tempBasalRate: Double? = nil, activeProfileName: String? = nil,
            activeProfilePercentage: Int? = nil
        ) {
            self.mgdl = mgdl
            self.trendRaw = trendRaw
            self.delta = delta
            self.date = date
            self.iob = iob
            self.unitsRaw = unitsRaw
            self.cob = cob
            self.tempBasalRate = tempBasalRate
            self.activeProfileName = activeProfileName
            self.activeProfilePercentage = activeProfilePercentage
        }
    }
    var title: String = "Glucose"
}
