import Foundation

final class NsTreatmentWriterLive: NsTreatmentWriter {
    /// Identifier used for both `app` (required by NS API v3) and `enteredBy`.
    static let appName = "AAPSClient-iOS"

    private let clientProvider: () -> NightscoutClient

    init(client: NightscoutClient) {
        self.clientProvider = { client }
    }

    init(clientProvider: @escaping @Sendable () -> NightscoutClient) {
        self.clientProvider = clientProvider
    }

    private var client: NightscoutClient { clientProvider() }

    func sendCarbs(grams: Double, at date: Date) async throws {
        try await client.postTreatment(Self.buildCarbs(grams: grams, at: date))
    }

    func sendTempTarget(targetMgdl: Int, durationMin: Int, reason: TtReason) async throws {
        try await client.postTreatment(Self.buildTempTarget(targetMgdl: targetMgdl, durationMin: durationMin, reason: reason))
    }

    func cancelTempTarget() async throws {
        try await client.postTreatment(Self.buildTempTargetCancel())
    }

    func switchProfile(name: String, percentage: Int, durationMin: Int, profileJson: String?) async throws {
        try await client.postTreatment(Self.buildProfileSwitch(name: name, percentage: percentage, durationMin: durationMin, profileJson: profileJson))
    }

    func logEvent(eventType: String, at date: Date, notes: String?, glucoseMgdl: Int?, durationMin: Int?) async throws {
        try await client.postTreatment(Self.buildEvent(eventType: eventType, at: date, notes: notes, glucoseMgdl: glucoseMgdl, durationMin: durationMin))
    }

    func setLoopMode(_ mode: String, durationMin: Int) async throws {
        try await client.postTreatment(Self.buildLoopMode(mode, durationMin: durationMin))
    }

    static func buildCarbs(grams: Double, at date: Date) -> [String: Any] {
        [
            "app": appName,
            "eventType": "Carb Correction",
            "carbs": grams,
            "date": Int64(date.timeIntervalSince1970 * 1000),
            "enteredBy": appName,
        ]
    }

    static func buildTempTarget(targetMgdl: Int, durationMin: Int, reason: TtReason) -> [String: Any] {
        [
            "app": appName,
            "eventType": "Temporary Target",
            "duration": durationMin,
            "targetBottom": targetMgdl,
            "targetTop": targetMgdl,
            "units": "mg/dl",
            "reason": reason.rawValue,
            "date": Int64(Date().timeIntervalSince1970 * 1000),
            "enteredBy": appName,
        ]
    }

    static func buildTempTargetCancel() -> [String: Any] {
        [
            "app": appName,
            "eventType": "Temporary Target",
            "duration": 0,
            "date": Int64(Date().timeIntervalSince1970 * 1000),
            "enteredBy": appName,
        ]
    }

    static func buildProfileSwitch(name: String, percentage: Int, durationMin: Int, profileJson: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "app": appName,
            "eventType": "Profile Switch",
            "profile": name,
            "percentage": percentage,
            "duration": durationMin,
            "date": Int64(Date().timeIntervalSince1970 * 1000),
            "enteredBy": appName,
        ]
        if let json = profileJson {
            payload["profileJson"] = json
        }
        return payload
    }

    static func buildEvent(eventType: String, at date: Date, notes: String?, glucoseMgdl: Int?, durationMin: Int?) -> [String: Any] {
        var payload: [String: Any] = [
            "app": appName,
            "eventType": eventType,
            "date": Int64(date.timeIntervalSince1970 * 1000),
            "enteredBy": appName,
        ]
        if let notes { payload["notes"] = notes }
        if let glucose = glucoseMgdl { payload["glucose"] = glucose; payload["units"] = "mg/dl" }
        if let dur = durationMin { payload["duration"] = dur }
        return payload
    }

    static func buildLoopMode(_ mode: String, durationMin: Int) -> [String: Any] {
        [
            "app": appName,
            "eventType": "OpenAPS Offline",
            "mode": mode,
            "duration": durationMin,
            "date": Int64(Date().timeIntervalSince1970 * 1000),
            "enteredBy": appName,
        ]
    }
}
