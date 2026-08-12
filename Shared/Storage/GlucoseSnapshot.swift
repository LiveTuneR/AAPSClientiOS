import Foundation

struct GlucoseSample: Codable, Equatable {
    let mgdl: Int
    let date: Date
}

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
    let history: [GlucoseSample]

    init(
        mgdl: Int, trend: TrendArrow, delta: Int?, date: Date,
        iob: Double?, cob: Double?, tempBasalRate: Double? = nil,
        activeProfileName: String? = nil, activeProfilePercentage: Int? = nil,
        history: [GlucoseSample] = []
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
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case mgdl, trend, delta, date, iob, cob, tempBasalRate
        case activeProfileName, activeProfilePercentage, history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mgdl = try c.decode(Int.self, forKey: .mgdl)
        trend = try c.decode(TrendArrow.self, forKey: .trend)
        delta = try c.decodeIfPresent(Int.self, forKey: .delta)
        date = try c.decode(Date.self, forKey: .date)
        iob = try c.decodeIfPresent(Double.self, forKey: .iob)
        cob = try c.decodeIfPresent(Double.self, forKey: .cob)
        tempBasalRate = try c.decodeIfPresent(Double.self, forKey: .tempBasalRate)
        activeProfileName = try c.decodeIfPresent(String.self, forKey: .activeProfileName)
        activeProfilePercentage = try c.decodeIfPresent(Int.self, forKey: .activeProfilePercentage)
        history = try c.decodeIfPresent([GlucoseSample].self, forKey: .history) ?? []
    }
}

struct DisplayConfig: Codable, Equatable {
    let units: GlucoseUnits
    let thresholds: AlarmThresholds
}
