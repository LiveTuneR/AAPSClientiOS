import Foundation

protocol NightscoutClient {
    func authorize() async throws
    func fetchEntries(limit: Int) async throws -> [GlucoseReading]
    func fetchTreatments(since: Date?) async throws -> [Treatment]
    func fetchDeviceStatus() async throws -> LoopStatus?
    func fetchProfile() async throws -> NsProfile
    func fetchProfileStore() async throws -> NsProfileStore
    func postTreatment(_ payload: [String: Any]) async throws
    /// Latest care-portal events (site/sensor/insulin/battery) — these are infrequent and fall
    /// outside the general treatments window, so they need a dedicated eventType-filtered query.
    func fetchCareEvents() async throws -> [Treatment]
    /// Paginated entries covering `days` back (live client pages past the NS per-request cap).
    /// MUST be a protocol requirement so calls via the protocol type dispatch to the live override,
    /// not the extension default below.
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading]
    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry]
}

extension NightscoutClient {
    func fetchCareEvents() async throws -> [Treatment] { try await fetchTreatments(since: nil) }
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading] { try await fetchEntries(limit: days * 320) }
    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry] { [] }
}
