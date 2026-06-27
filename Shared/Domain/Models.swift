import Foundation

enum TrendArrow: String, Codable {
    case doubleUp, singleUp, fortyFiveUp, flat, fortyFiveDown, singleDown, doubleDown, none
}

enum GlucoseClassification {
    case urgentLow, low, inRange, high, urgentHigh
}

enum GlucoseUnits: String, Codable {
    case mgdl = "mg/dl"
    case mmol = "mmol/l"

    /// Lenient parse of a Nightscout/AAPS units string. Profiles commonly use
    /// "mmol", "mmol/L", or "mmol/l" — the strict rawValue only matches "mmol/l",
    /// so anything containing "mmol" maps to .mmol, everything else to .mgdl.
    init(nsUnits: String?) {
        self = (nsUnits?.lowercased().contains("mmol") == true) ? .mmol : .mgdl
    }
}

struct GlucoseReading: Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let mgdl: Int
    let trend: TrendArrow
}

struct LoopStatus: Equatable {
    let iob: Double
    let cob: Double
    let eventualBgMgdl: Int?
    let tempBasalRate: Double?
    let suggestedReason: String?
    let timestamp: Date
    let predictions: Predictions?
    let pumpBattery: Int?
    let pumpReservoir: Double?
    let uploaderBattery: Int?
    let reason: LoopReason?
}

struct DeviceStatusEntry: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let iob: Double
    let cob: Double
}

struct Predictions: Equatable {
    let iob: [Int]
    let cob: [Int]
    let zt: [Int]
    let uam: [Int]
}

struct Treatment: Equatable, Identifiable {
    let id: String
    let eventType: String
    let date: Date
    let insulin: Double?
    let carbs: Double?
    let durationMin: Int?
    let enteredBy: String?
    let notes: String?
    let targetBottom: Int?
    let targetTop: Int?
    let profileName: String?
    let percentage: Int?
    let absolute: Double?
    let tempBasalPercent: Int?
}

struct NsProfile: Equatable {
    let units: GlucoseUnits
    let dia: Double?
    let basal: [BasalEntry]
    let targetLow: [ScheduledValue]
    let targetHigh: [ScheduledValue]
    let carbRatio: [ScheduledValue]
    let sensitivity: [ScheduledValue]
}

struct NsProfileStore: Equatable {
    let defaultProfileName: String
    let profileNames: [String]
    let rawJson: [String: String]
    let active: NsProfile
}

struct BasalEntry: Equatable {
    let startSeconds: Int
    let rate: Double
}

struct ScheduledValue: Equatable {
    let startSeconds: Int
    let value: Double
}

struct EditableBlock: Identifiable {
    let id = UUID()
    var startSeconds: Int
    var valueString: String
}

struct AlarmThresholds: Equatable, Codable {
    let urgentLow: Int
    let low: Int
    let high: Int
    let urgentHigh: Int
    let staleMinutes: Int

    static let defaults = AlarmThresholds(
        urgentLow: 55, low: 70, high: 180, urgentHigh: 250, staleMinutes: 15
    )
}

enum AlarmType: Equatable, Hashable {
    case urgentLow, low, high, urgentHigh, noData, connectionLost
}

enum TtReason: String {
    case eatingSoon = "Eating Soon"
    case activity = "Activity"
    case hypo = "Hypo"
    case custom = "Custom"

    var defaultTargetMgdl: Int {
        switch self {
        case .eatingSoon: return 90
        case .activity:   return 140
        case .hypo:       return 150
        case .custom:     return 110
        }
    }

    var defaultDurationMin: Int {
        switch self {
        case .eatingSoon: return 45
        case .activity:   return 90
        case .hypo:       return 60
        case .custom:     return 60
        }
    }
}

struct TtPreset: Equatable, Codable {
    var targetMgdl: Int
    var durationMin: Int
}

struct LoopReason: Equatable {
    let isfMgdl: Double?
    let cr: Double?
    let targetMgdl: Int?
    let tdd: Double?
    let deviation: Double?
    let bgi: Double?
    let minPredBg: Int?
    let iobPredBg: Int?
    let cobPredBg: Int?
    var isEmpty: Bool {
        isfMgdl == nil && cr == nil && targetMgdl == nil && tdd == nil
            && deviation == nil && bgi == nil && minPredBg == nil
            && iobPredBg == nil && cobPredBg == nil
    }
}

enum NsError: LocalizedError {
    case noNetwork
    case unauthorized
    case badURL
    case decoding(String)
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .noNetwork:      return String(localized: "error.no_network")
        case .unauthorized:   return String(localized: "error.unauthorized")
        case .badURL:         return String(localized: "error.bad_url")
        case .decoding(let d): return String(localized: "error.decoding") + ": \(d)"
        case .server(let c):  return String(format: String(localized: "error.server"), c)
        }
    }
}

/// Conversion factor between mg/dl and mmol/l for glucose.
/// mmol/l = mg/dl / glucoseMmolFactor
let glucoseMmolFactor = 18.0182

func convertUnit(value: Double, from: GlucoseUnits, to: GlucoseUnits) -> Double {
    if from == to { return value }
    return from == .mgdl ? value / glucoseMmolFactor : value * glucoseMmolFactor
}
