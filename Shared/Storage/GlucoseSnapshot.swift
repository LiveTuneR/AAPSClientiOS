import Foundation

struct GlucoseSnapshot: Codable, Equatable {
    let mgdl: Int
    let trend: TrendArrow
    let delta: Int?       // mg/dl, vs previous reading
    let date: Date
    let iob: Double?
    let cob: Double?
    let tempBasalRate: Double?
    let activeProfileName: String?
    let activeProfilePercentage: Int?

    init(
        mgdl: Int, trend: TrendArrow, delta: Int?, date: Date,
        iob: Double?, cob: Double?, tempBasalRate: Double? = nil,
        activeProfileName: String? = nil, activeProfilePercentage: Int? = nil
    ) {
        self.mgdl = mgdl
        self.trend = trend
        self.delta = delta
        self.date = date
        self.iob = iob
        self.cob = cob
        self.tempBasalRate = tempBasalRate
        self.activeProfileName = activeProfileName
        self.activeProfilePercentage = activeProfilePercentage
    }
}

struct DisplayConfig: Codable, Equatable {
    let units: GlucoseUnits
    let thresholds: AlarmThresholds
}
