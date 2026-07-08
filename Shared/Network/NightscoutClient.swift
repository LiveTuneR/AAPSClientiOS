import Foundation

protocol NightscoutClient: Sendable {
    func authorize() async throws
    func fetchEntries(limit: Int) async throws -> [GlucoseReading]
    func fetchTreatments(since: Date?) async throws -> [Treatment]
    func fetchDeviceStatus() async throws -> LoopStatus?
    func fetchProfile() async throws -> NsProfile
    func fetchProfileStore() async throws -> NsProfileStore
    func fetchSettings(identifier: String) async throws -> NsSettingsDocument?
    func fetchRunningConfigCold() async throws -> NsRunningConfigCold?
    func fetchRunningConfigHot() async throws -> NsRunningConfigHot?
    func postTreatment(_ payload: [String: Any]) async throws
    /// Latest care-portal events (site/sensor/insulin/battery) — these are infrequent and fall
    /// outside the general treatments window, so they need a dedicated eventType-filtered query.
    func fetchCareEvents() async throws -> [Treatment]
    /// Paginated entries covering `days` back (live client pages past the NS per-request cap).
    /// MUST be a protocol requirement so calls via the protocol type dispatch to the live override,
    /// not the extension default below.
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading]
    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry]
    /// Treatments covering `since` to now, paginated by the treatment `date` field (not
    /// `srvModified`). MUST be a protocol requirement — see `fetchEntries(sinceDays:)` above
    /// for why an extension-only default would silently shadow the live client's real paging.
    func fetchTreatmentsHistory(since: Date) async throws -> [Treatment]
}

extension NightscoutClient {
    func fetchCareEvents() async throws -> [Treatment] { try await fetchTreatments(since: nil) }
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading] { try await fetchEntries(limit: days * 320) }
    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry] { [] }
    func fetchTreatmentsHistory(since: Date) async throws -> [Treatment] {
        try await fetchTreatments(since: nil).filter { $0.date >= since }
    }
    func fetchRunningConfigCold() async throws -> NsRunningConfigCold? {
        guard let document = try await fetchSettings(identifier: NightscoutSettingsIdentifier.cold) else { return nil }
        return try NsMapping.runningConfigCold(from: document)
    }
    func fetchRunningConfigHot() async throws -> NsRunningConfigHot? {
        guard let document = try await fetchSettings(identifier: NightscoutSettingsIdentifier.state) else { return nil }
        return try NsMapping.runningConfigHot(from: document)
    }
}

enum NightscoutSettingsIdentifier {
    static let cold = "aaps"
    static let state = "aaps-state"
}
