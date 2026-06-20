import Foundation

struct GlucoseSnapshot: Codable, Equatable {
    let mgdl: Int
    let trend: TrendArrow
    let delta: Int?       // mg/dl, vs previous reading
    let date: Date
    let iob: Double?
    let cob: Double?
}

struct DisplayConfig: Codable, Equatable {
    let units: GlucoseUnits
    let thresholds: AlarmThresholds
}
