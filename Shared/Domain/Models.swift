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

struct Treatment: Equatable, Identifiable, Codable {
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

    static func activeTempTarget(in treatments: [Treatment], now: Date = Date()) -> Treatment? {
        guard let latest = treatments
            .filter({ $0.eventType == "Temporary Target" && $0.date <= now })
            .max(by: { $0.date < $1.date }),
              let duration = latest.durationMin,
              duration > 0,
              latest.targetBottom != nil || latest.targetTop != nil,
              latest.date.addingTimeInterval(Double(duration) * 60) > now else {
            return nil
        }
        return latest
    }

    static func mergedHistoryWindow(
        existing: [Treatment],
        incoming: [Treatment],
        now: Date = Date(),
        days: Int = 7
    ) -> [Treatment] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var byID: [String: Treatment] = [:]

        for treatment in existing where treatment.date >= cutoff {
            byID[treatment.id] = treatment
        }
        for treatment in incoming where treatment.date >= cutoff {
            byID[treatment.id] = treatment
        }

        return byID.values.sorted { $0.date > $1.date }
    }
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

struct NsSettingsDocument: Equatable, Sendable {
    let identifier: String
    let app: String?
    let schemaVersion: Int?
    let date: Date?
    let srvModified: Date?
    let runningConfigJson: String
}

struct NsAuthorizedClients: Equatable, Sendable {
    let clientIds: [String]
}

struct NsActiveScene: Equatable, Sendable {
    let sceneId: String?
    let activatedAt: Date?
    let durationMs: Int?
    let lifecycle: String?
    let ttNsId: String?
    let psNsId: String?
    let rmNsId: String?
    let teNsId: String?
}

struct NsSyncedPrefsSnapshot: Equatable, Sendable {
    let rawValues: [String: String]

    var activePluginAps: String? { rawValues["ActivePluginAps"] }
    var activePluginSensitivity: String? { rawValues["ActivePluginSensitivity"] }
    var activePluginSmoothing: String? { rawValues["ActivePluginSmoothing"] }
    var activePluginCalibration: String? { rawValues["ActivePluginCalibration"] }
    var tempTargetPresetsJson: String? { rawValues["TempTargetPresets"] ?? rawValues["temp_target_presets"] }
    var quickWizardJson: String? { rawValues["QuickWizard"] }
    var sceneDefinitionsJson: String? { rawValues["SceneDefinitions"] }
}

struct NsRunningConfigCold: Equatable, Sendable {
    var pump: String?
    var version: String?
    var isFakingTempsByExtendedBoluses: Bool?
    var syncedPrefs: [String: String]
    var authorizedClientIds: [String]
    var srvModified: Date?

    var syncedPrefsSnapshot: NsSyncedPrefsSnapshot {
        NsSyncedPrefsSnapshot(rawValues: syncedPrefs)
    }

    var remoteCapabilities: NsRemoteCapabilities {
        NsRemoteCapabilities(syncedPrefs: syncedPrefs)
    }
}

struct NsRunningConfigHot: Equatable, Sendable {
    var activeScene: NsActiveScene?
    var usedAutosensOnMainPhone: Bool?
    var srvModified: Date?
}

struct NsRemoteCapabilities: Equatable, Sendable {
    let canReceiveProfileStore: Bool
    let canRemoteProfileSwitch: Bool
    let canRemoteTempTarget: Bool
    let canRemoteCarbs: Bool
    let canRemoteTherapyEvents: Bool
    let canRemoteRunningMode: Bool
    let canRemoteTbrEb: Bool
    let clientControlEnabled: Bool
    let usesWebSockets: Bool

    init(syncedPrefs: [String: String]) {
        canReceiveProfileStore = Self.boolFlag(["NsClientAcceptProfileStore", "ns_receive_profile_store"], in: syncedPrefs)
        canRemoteProfileSwitch = Self.boolFlag(["NsClientAcceptProfileSwitch", "ns_receive_profile_switch"], in: syncedPrefs)
        canRemoteTempTarget = Self.boolFlag(["NsClientAcceptTempTarget", "ns_receive_temp_target"], in: syncedPrefs)
        canRemoteCarbs = Self.boolFlag(["NsClientAcceptCarbs", "ns_receive_carbs"], in: syncedPrefs)
        canRemoteTherapyEvents = Self.boolFlag(["NsClientAcceptTherapyEvent", "ns_receive_therapy_events"], in: syncedPrefs)
        canRemoteRunningMode = Self.boolFlag(["NsClientAcceptRunningMode", "ns_receive_running_mode"], in: syncedPrefs)
        canRemoteTbrEb = Self.boolFlag(["NsClientAcceptTbrEb", "ns_receive_tbr_eb"], in: syncedPrefs)
        clientControlEnabled = Self.boolFlag(["NsClientAllowClientControl", "ns_allow_client_control"], in: syncedPrefs)
        usesWebSockets = Self.boolFlag(["NsClient3UseWs", "ns_use_ws"], in: syncedPrefs)
    }

    private static func boolFlag(_ keys: [String], in syncedPrefs: [String: String]) -> Bool {
        let normalized = Dictionary(
            uniqueKeysWithValues: syncedPrefs.map { key, value in
                (normalize(key), value)
            }
        )
        return keys.contains { key in
            guard let raw = normalized[normalize(key)]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return false
            }
            return raw == "true" || raw == "1"
        }
    }

    private static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension NsRemoteCapabilities {
    func isEnabled(for key: NsRemoteCapabilityKey) -> Bool {
        switch key {
        case .profileSwitch: return canRemoteProfileSwitch
        case .tempTarget: return canRemoteTempTarget
        case .carbs: return canRemoteCarbs
        case .therapyEvents: return canRemoteTherapyEvents
        case .runningMode: return canRemoteRunningMode
        }
    }
}

enum NsRemoteCapabilityKey: String, Sendable {
    case profileSwitch = "NsClientAcceptProfileSwitch"
    case tempTarget = "NsClientAcceptTempTarget"
    case carbs = "NsClientAcceptCarbs"
    case therapyEvents = "NsClientAcceptTherapyEvent"
    case runningMode = "NsClientAcceptRunningMode"

    var localizationKey: String {
        switch self {
        case .profileSwitch: return "remote.capability.profile"
        case .tempTarget: return "remote.capability.target"
        case .carbs: return "remote.capability.carbs"
        case .therapyEvents: return "remote.capability.events"
        case .runningMode: return "remote.capability.loop"
        }
    }
}

struct NsSyncedTempTargetPreset: Equatable, Identifiable, Sendable {
    let name: String
    let targetMgdl: Int
    let durationMin: Int

    var id: String { name }
}

struct NsSceneDefinition: Equatable, Identifiable, Sendable {
    let sceneId: String
    let name: String?

    var id: String { sceneId }
}

struct NsQuickWizardEntry: Equatable, Identifiable, Sendable {
    let name: String
    let carbs: Int?
    let percentage: Int?
    let note: String?

    var id: String { name }
}

enum NsSyncedPrefsParser {
    static func tempTargetPresets(from json: String?) -> [NsSyncedTempTargetPreset] {
        guard let items = jsonArray(from: json) else { return [] }
        return items.compactMap { item in
            let name = firstString(in: item, keys: ["name", "displayName", "label"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            let durationMin = int(item["durationMin"]) ?? int(item["duration"]) ?? int(item["minutes"])
            let rawTarget = number(item["targetMgdl"]) ?? number(item["target"]) ?? number(item["targetBottom"]) ?? number(item["targetTop"])
            guard let durationMin, durationMin > 0, let rawTarget else { return nil }
            let targetMgdl = normalizeGlucoseTarget(rawTarget)
            return NsSyncedTempTargetPreset(name: name, targetMgdl: targetMgdl, durationMin: durationMin)
        }
    }

    static func sceneDefinitions(from json: String?) -> [NsSceneDefinition] {
        guard let items = jsonArray(from: json) else { return [] }
        return items.compactMap { item in
            guard let sceneId = firstString(in: item, keys: ["sceneId", "id"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sceneId.isEmpty else { return nil }
            let name = firstString(in: item, keys: ["name", "title", "displayName"])
            return NsSceneDefinition(sceneId: sceneId, name: name)
        }
    }

    static func quickWizardEntries(from json: String?) -> [NsQuickWizardEntry] {
        guard let items = jsonArray(from: json) else { return [] }
        return items.compactMap { item in
            guard let name = firstString(in: item, keys: ["name", "buttonText", "label"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return NsQuickWizardEntry(
                name: name,
                carbs: int(item["carbs"]) ?? int(item["carbInput"]),
                percentage: int(item["percentage"]),
                note: firstString(in: item, keys: ["note", "notes", "description"])
            )
        }
    }

    private static func jsonArray(from json: String?) -> [[String: Any]]? {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return object as? [[String: Any]]
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        number(value).map { Int($0) }
    }

    private static func normalizeGlucoseTarget(_ value: Double) -> Int {
        let mgdl = value < 40 ? value * glucoseMmolFactor : value
        return Int(mgdl.rounded())
    }
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

struct ConsumableThresholds: Equatable, Codable {
    let cageWarnHours: Int
    let cageCriticalHours: Int
    let iageWarnHours: Int
    let iageCriticalHours: Int
    let sageWarnHours: Int
    let sageCriticalHours: Int
    let bageWarnHours: Int
    let bageCriticalHours: Int
    let reservoirWarnUnits: Int
    let reservoirCriticalUnits: Int
    let pumpBattWarnPercent: Int
    let pumpBattCriticalPercent: Int

    static let defaults = ConsumableThresholds(
        cageWarnHours: 48, cageCriticalHours: 72,
        iageWarnHours: 72, iageCriticalHours: 144,
        sageWarnHours: 216, sageCriticalHours: 240,
        bageWarnHours: 216, bageCriticalHours: 240,
        reservoirWarnUnits: 80, reservoirCriticalUnits: 10,
        pumpBattWarnPercent: 51, pumpBattCriticalPercent: 26
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

enum SettingsValueConverter {
    static func convert(_ text: String, from: GlucoseUnits, to: GlucoseUnits) -> String {
        guard from != to, let value = Double(text) else { return text }
        let converted = convertUnit(value: value, from: from, to: to)
        return to == .mmol
            ? String(format: "%.1f", converted)
            : String(Int(converted.rounded()))
    }
}

func liveActivityStaleDate(for readingDate: Date, staleMinutes: Int = 15) -> Date {
    readingDate.addingTimeInterval(Double(staleMinutes) * 60)
}
