import XCTest
@testable import AAPSClientiOS

final class NightscoutReadTests: XCTestCase {

    func test_fetchEntriesReturnsParsedData() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        let fixture = try loadFixture("entries")
        transport.responseData = fixture
        let entries = try await client.fetchEntries(limit: 10)

        XCTAssertEqual(transport.lastRequest?.url?.absoluteString.contains("api/v3/entries"), true)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].mgdl, 120)
        XCTAssertEqual(entries[0].trend, .flat)
    }

    func test_fetchTreatmentsReturnsParsedData() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        let fixture = try loadFixture("treatments")
        transport.responseData = fixture
        let treatments = try await client.fetchTreatments()

        XCTAssertEqual(treatments.count, 4)
        XCTAssertEqual(treatments[0].eventType, "Meal Bolus")
    }

    func test_fetchTreatmentsWithSinceAddsSrvModifiedFilter() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        transport.responseData = #"{"status":200,"result":[]}"# .data(using: .utf8)!
        let since = Date(timeIntervalSince1970: 1000)
        _ = try await client.fetchTreatments(since: since)

        let url = transport.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("srvModified$gte="))
    }

    func test_fetchDeviceStatusReturnsLoopStatus() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        let fixture = try loadFixture("devicestatus")
        transport.responseData = fixture
        let status = try await client.fetchDeviceStatus()

        XCTAssertEqual(status?.iob, 1.85)
        XCTAssertEqual(status?.cob, 24.0)
    }

    func test_fetchProfileReturnsParsedProfile() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        let fixture = try loadFixture("profile")
        transport.responseData = fixture
        let profile = try await client.fetchProfile()

        XCTAssertEqual(profile.units, .mgdl)
        XCTAssertEqual(profile.basal.count, 3)
    }

    func test_urlHasNoDoubleSlash() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        transport.responseData = #"{"status":200,"result":[]}"# .data(using: .utf8)!
        _ = try await client.fetchEntries(limit: 10)

        let url = transport.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("test.nightscout.example.com/api/v3/entries"))
        XCTAssertFalse(url.contains("//api"))
    }

    func test_serverErrorThrowsServerCase() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"# .data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        transport.responseCode = 500
        transport.responseData = Data()

        do {
            _ = try await client.fetchEntries(limit: 10)
            XCTFail("Expected error")
        } catch {
        }
    }

    func test_fetchDeviceStatusHistoryURL() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"#.data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        transport.responseData = try loadFixture("devicestatus_history")
        let since = Date(timeIntervalSince1970: 1_718_571_600)
        let entries = try await client.fetchDeviceStatusHistory(since: since)

        let url = transport.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("api/v3/devicestatus"))
        XCTAssertTrue(url.contains("sort$desc=date"))
        XCTAssertTrue(url.contains("limit=288"))
        XCTAssertTrue(url.contains("date$gt=1718571600000"))
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries[0].iob, 1.20, accuracy: 0.001)
    }

    func test_fetchRunningConfigColdUsesAapsSettingsEndpoint() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"#.data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        transport.responseData = try loadFixture("settings_aaps")
        let cold = try await client.fetchRunningConfigCold()

        let url = transport.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("api/v3/settings/aaps"))
        XCTAssertEqual(cold?.pump, "Dana-i")
        XCTAssertTrue(cold?.remoteCapabilities.canRemoteProfileSwitch == true)
    }

    func test_fetchRunningConfigHotUsesStateSettingsEndpoint() async throws {
        let transport = MockAuthTransport()
        transport.responseData = #"{"token":"jwt","iat":1,"exp":99999}"#.data(using: .utf8)!
        let client = NightscoutClientLive(baseURL: testBaseURL, accessToken: "t", transport: transport)
        try await client.authorize()

        transport.responseData = try loadFixture("settings_aaps_state")
        let hot = try await client.fetchRunningConfigHot()

        let url = transport.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("api/v3/settings/aaps-state"))
        XCTAssertEqual(hot?.activeScene?.sceneId, "school-sport")
        XCTAssertEqual(hot?.usedAutosensOnMainPhone, true)
    }
}
