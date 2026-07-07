import XCTest
@testable import AAPSClientiOS

let testBaseURL = URL(string: "https://test.nightscout.example.com")!

final class MockAuthTransport: HttpTransport {
    var responseData: Data = Data()
    var responseCode: Int = 200
    var lastRequest: URLRequest?

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: responseCode, httpVersion: nil, headerFields: nil
        )!
        return (responseData, response)
    }
}

final class FixtureNightscoutClient: NightscoutClient {
    var postedPayloads: [[String: Any]] = []
    var shouldThrow: Error?
    /// Simulate a Task cancelled mid-refresh: entries succeed, later stages throw
    /// CancellationError (the real-world trigger for the frozen widget/LA bug).
    var cancelAfterEntries = false
    var settingsByIdentifier: [String: String] = [
        NightscoutSettingsIdentifier.cold: "settings_aaps",
        NightscoutSettingsIdentifier.state: "settings_aaps_state",
    ]

    func authorize() async throws {
        if let error = shouldThrow { throw error }
    }

    func fetchEntries(limit: Int) async throws -> [GlucoseReading] {
        if let error = shouldThrow { throw error }
        let data = try loadFixture("entries")
        return try NsMapping.glucose(from: data)
    }

    func fetchTreatments(since: Date?) async throws -> [Treatment] {
        if cancelAfterEntries { throw CancellationError() }
        if let error = shouldThrow { throw error }
        let data = try loadFixture("treatments")
        return try NsMapping.treatments(from: data)
    }

    func fetchDeviceStatus() async throws -> LoopStatus? {
        if cancelAfterEntries { throw CancellationError() }
        if let error = shouldThrow { throw error }
        let data = try loadFixture("devicestatus")
        return try NsMapping.loopStatus(from: data)
    }

    func fetchProfile() async throws -> NsProfile {
        if let error = shouldThrow { throw error }
        let data = try loadFixture("profile")
        return try NsMapping.profile(from: data)
    }

    func fetchProfileStore() async throws -> NsProfileStore {
        if let error = shouldThrow { throw error }
        let data = try loadFixture("profile")
        return try NsMapping.profileStore(from: data)
    }

    func fetchSettings(identifier: String) async throws -> NsSettingsDocument? {
        if let error = shouldThrow { throw error }
        guard let fixture = settingsByIdentifier[identifier] else { return nil }
        let data = try loadFixture(fixture)
        return try NsMapping.settingsDocument(from: data, identifier: identifier)
    }

    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading] {
        if let error = shouldThrow { throw error }
        let data = try loadFixture("entries")
        return try NsMapping.glucose(from: data)
    }

    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry] {
        if let error = shouldThrow { throw error }
        let data = try loadFixture("devicestatus_history")
        return try NsMapping.deviceStatusHistory(from: data)
    }

    func postTreatment(_ payload: [String: Any]) async throws {
        if let error = shouldThrow { throw error }
        postedPayloads.append(payload)
    }
}
