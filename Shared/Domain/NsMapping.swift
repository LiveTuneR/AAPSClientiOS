import Foundation

/// Maps Nightscout API v3 JSON to domain models.
///
/// IMPORTANT: parsing goes through `JSONSerialization`, NOT `JSONDecoder`.
/// The iOS 18+ swift-foundation `JSONDecoder` number parser throws
/// "Number 82.8000000000001 is not representable in Swift" (dataCorrupted)
/// on high-precision floats that AAPS/OpenAPS commonly emit (iob, cob, etc.).
/// `JSONSerialization` parses those into `NSNumber` without error, so we map
/// manually from the resulting dictionaries.
enum NsMapping {

    // MARK: - Public mappers

    static func glucose(from data: Data) throws -> [GlucoseReading] {
        try resultArray(data)
            .filter { ($0["type"] as? String) == "sgv" }
            .compactMap { d in
                guard let sgv = num(d["sgv"]) else { return nil }
                return GlucoseReading(
                    date: date(from: num(d["date"])),
                    mgdl: Int(sgv),
                    trend: TrendArrow.from(nsDirection: d["direction"] as? String)
                )
            }
    }

    static func treatments(from data: Data) throws -> [Treatment] {
        try resultArray(data).map { d in
            let ts = num(d["date"]) ?? num(d["mills"]) ?? num(d["timestamp"])
            let createdAt = (d["created_at"] as? String).flatMap(isoParse)
            return Treatment(
                id: (d["identifier"] as? String) ?? (d["_id"] as? String) ?? UUID().uuidString,
                eventType: (d["eventType"] as? String) ?? "",
                date: ts.map { Date(timeIntervalSince1970: $0 / 1000) } ?? createdAt ?? Date(),
                insulin: num(d["insulin"]),
                carbs: num(d["carbs"]),
                durationMin: intVal(d["duration"]),
                enteredBy: d["enteredBy"] as? String,
                notes: d["notes"] as? String,
                targetBottom: parseTTTarget(from: d).bottom,
                targetTop: parseTTTarget(from: d).top,
                profileName: d["profile"] as? String,
                percentage: intVal(d["percentage"])
            )
        }
    }

    static func loopStatus(from data: Data) throws -> LoopStatus? {
        guard let latest = try resultArray(data).first else { return nil }

        let openaps = latest["openaps"] as? [String: Any]
        let enacted = openaps?["enacted"] as? [String: Any]
        let suggested = openaps?["suggested"] as? [String: Any]
        let active = enacted ?? suggested
        let iobObj = openaps?["iob"] as? [String: Any]
        let pump = latest["pump"] as? [String: Any]
        let battery = pump?["battery"] as? [String: Any]

        return LoopStatus(
            iob: num(active?["iob"]) ?? num(iobObj?["iob"]) ?? 0,
            cob: num(active?["cob"]) ?? num(active?["COB"]) ?? 0,
            eventualBgMgdl: intVal(active?["eventualBG"]) ?? intVal(suggested?["eventualBG"]),
            tempBasalRate: num(active?["rate"]),
            suggestedReason: active?["reason"] as? String,
            timestamp: (active?["timestamp"] as? String).flatMap(isoParse) ?? Date(),
            predictions: predictions(from: suggested) ?? predictions(from: enacted),
            pumpBattery: intVal(battery?["percent"]),
            pumpReservoir: num(pump?["reservoir"]),
            uploaderBattery: intVal(latest["uploaderBattery"]),
            reason: parseReason(from: enacted ?? suggested)
        )
    }

    static func deviceStatusHistory(from data: Data) throws -> [DeviceStatusEntry] {
        try resultArray(data).compactMap { d in
            guard let ts = num(d["date"]) else { return nil }
            let openaps = d["openaps"] as? [String: Any]
            let enacted = openaps?["enacted"] as? [String: Any]
            let suggested = openaps?["suggested"] as? [String: Any]
            let active = enacted ?? suggested
            let iobObj = openaps?["iob"] as? [String: Any]
            let iob = num(active?["iob"]) ?? num(iobObj?["iob"]) ?? 0
            let cob = num(active?["cob"]) ?? num(active?["COB"]) ?? 0
            return DeviceStatusEntry(date: date(from: ts), iob: iob, cob: cob)
        }
    }

    static func profile(from data: Data) throws -> NsProfile {
        guard let latest = try resultArray(data).first,
              let store = latest["store"] as? [String: Any],
              let defaultName = latest["defaultProfile"] as? String,
              let prof = store[defaultName] as? [String: Any] else {
            throw NsError.decoding("No default profile found")
        }
        return parseProfileObject(prof)
    }

    static func parseProfileObject(_ prof: [String: Any]) -> NsProfile {
        func schedule(_ key: String) -> [(Int, Double)] {
            (prof[key] as? [[String: Any]])?.compactMap {
                guard let t = intVal($0["timeAsSeconds"]), let v = num($0["value"]) else { return nil }
                return (t, v)
            } ?? []
        }

        return NsProfile(
            units: GlucoseUnits(nsUnits: prof["units"] as? String),
            dia: num(prof["dia"]),
            basal: schedule("basal").map { BasalEntry(startSeconds: $0.0, rate: $0.1) },
            targetLow: schedule("target_low").map { ScheduledValue(startSeconds: $0.0, value: $0.1) },
            targetHigh: schedule("target_high").map { ScheduledValue(startSeconds: $0.0, value: $0.1) },
            carbRatio: schedule("carbratio").map { ScheduledValue(startSeconds: $0.0, value: $0.1) },
            sensitivity: schedule("sens").map { ScheduledValue(startSeconds: $0.0, value: $0.1) }
        )
    }

    static func profileStore(from data: Data) throws -> NsProfileStore {
        guard let latest = try resultArray(data).first,
              let store = latest["store"] as? [String: Any],
              let defaultName = latest["defaultProfile"] as? String else {
            throw NsError.decoding("No default profile found")
        }
        let names = Array(store.keys)
        let rawJson: [String: String] = names.reduce(into: [:]) { d, name in
            if let obj = store[name] as? [String: Any],
               let jd = try? JSONSerialization.data(withJSONObject: obj),
               let str = String(data: jd, encoding: .utf8) {
                d[name] = str
            }
        }
        let active = try profile(from: data)
        return NsProfileStore(
            defaultProfileName: defaultName,
            profileNames: names,
            rawJson: rawJson,
            active: active
        )
    }

    // MARK: - Private helpers

    private static func resultArray(_ data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dict = object as? [String: Any] else {
            throw NsError.decoding("Unexpected NS v3 response shape")
        }
        return (dict["result"] as? [[String: Any]]) ?? []
    }

    private static func predictions(from src: [String: Any]?) -> Predictions? {
        guard let p = src?["predBGs"] as? [String: Any] else { return nil }
        func arr(_ key: String) -> [Int] {
            (p[key] as? [Any])?.compactMap { intVal($0) } ?? []
        }
        return Predictions(iob: arr("IOB"), cob: arr("COB"), zt: arr("ZT"), uam: arr("UAM"))
    }

    private static func num(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func intVal(_ value: Any?) -> Int? {
        num(value).map { Int($0) }
    }

    private static func date(from millis: Double?) -> Date {
        millis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
    }

    private static func parseReason(from enacted: [String: Any]?) -> LoopReason {
        guard let e = enacted else { return LoopReason(isfMgdl: nil, cr: nil, targetMgdl: nil, tdd: nil, deviation: nil, bgi: nil, minPredBg: nil, iobPredBg: nil, cobPredBg: nil) }
        return LoopReason(
            isfMgdl: num(e["ISF"]) ?? num(e["variable_sens"]),
            cr: num(e["CR"]),
            targetMgdl: intVal(e["current_target"]) ?? intVal(e["target_bg"]),
            tdd: num(e["TDD"]) ?? num(e["insulin"]),
            deviation: num(e["deviation"]),
            bgi: num(e["BGI"]),
            minPredBg: intVal(e["minPredBG"]),
            iobPredBg: intVal(e["IOBpredBG"]),
            cobPredBg: intVal(e["COBpredBG"])
        )
    }

    private static func parseTTTarget(from d: [String: Any]) -> (bottom: Int?, top: Int?) {
        let eventType = d["eventType"] as? String ?? ""
        guard eventType == "Temporary Target" else { return (nil, nil) }
        let duration = intVal(d["duration"]) ?? 0
        if duration == 0 { return (nil, nil) }

        func normalize(_ v: Double?) -> Int? {
            guard var value = v else { return nil }
            if value < 40 { value *= 18.0182 }
            return Int(value.rounded())
        }

        let rawBottom = num(d["targetBottom"]) ?? num(d["targetBottomMgdl"])
        let rawTop = num(d["targetTop"]) ?? num(d["targetTopMgdl"])

        if let b = rawBottom ?? rawTop {
            let bottom = normalize(rawBottom ?? b)
            let top = normalize(rawTop ?? b)
            return (bottom, top)
        }

        if let rawTarget = num(d["target"]) {
            let v = normalize(rawTarget)
            return (v, v)
        }

        for key in ["reason", "notes"] {
            if let s = d[key] as? String, let n = Double(s.split(separator: " ").first ?? "") {
                let v = normalize(n)
                return (v, v)
            }
        }
        return (nil, nil)
    }
}

// MARK: - TrendArrow helper

extension TrendArrow {
    static func from(nsDirection: String?) -> TrendArrow {
        switch nsDirection {
        case "DoubleUp": return .doubleUp
        case "SingleUp": return .singleUp
        case "FortyFiveUp": return .fortyFiveUp
        case "Flat": return .flat
        case "FortyFiveDown": return .fortyFiveDown
        case "SingleDown": return .singleDown
        case "DoubleDown": return .doubleDown
        default: return .none
        }
    }
}

// MARK: - ISO 8601 parse

private func isoParse(_ string: String) -> Date? {
    ISO8601DateFormatter().date(from: string)
}
