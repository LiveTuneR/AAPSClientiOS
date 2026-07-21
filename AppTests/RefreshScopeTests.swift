import XCTest
@testable import AAPSClientiOS

final class CountingNightscoutClient: FixtureNightscoutClient {
    var entriesCalls = 0
    var deviceStatusCalls = 0
    var treatmentsCalls = 0
    var profileCalls = 0

    override func fetchEntries(limit: Int) async throws -> [GlucoseReading] {
        entriesCalls += 1
        return try await super.fetchEntries(limit: limit)
    }

    override func fetchDeviceStatus() async throws -> LoopStatus? {
        deviceStatusCalls += 1
        return try await super.fetchDeviceStatus()
    }

    override func fetchTreatments(since: Date?) async throws -> [Treatment] {
        treatmentsCalls += 1
        return try await super.fetchTreatments(since: since)
    }

    override func fetchProfile() async throws -> NsProfile {
        profileCalls += 1
        return try await super.fetchProfile()
    }
}

final class RefreshScopeTests: XCTestCase {
    // A light refresh proves the connection is alive, so it must count as a
    // successful update for alarm staleness. Otherwise the stale check in
    // AlarmEngineLive.evaluate short-circuits to .noData and returns before it
    // ever compares glucose against the thresholds — spurious "No Data" alarms
    // every few minutes, and real low/high alarms silently never fire in the
    // background.
    @MainActor
    func test_lightRefresh_doesNotFireStaleNoDataAlarm() async throws {
        let notifier = MockNotifier()
        let store = AppStore(
            client: FixtureNightscoutClient(),
            alarmEngine: AlarmEngineLive(notifier: notifier)
        )

        try await store.refresh(scope: .light)

        XCTAssertFalse(
            notifier.posted.contains { $0.identifier == "alarm.noData" },
            "light refresh just fetched fresh data; it must not report it as stale"
        )
    }

    @MainActor
    func test_lightRefresh_stillEvaluatesGlucoseThresholds() async throws {
        let notifier = MockNotifier()
        let store = AppStore(
            client: FixtureNightscoutClient(),
            alarmEngine: AlarmEngineLive(notifier: notifier)
        )
        // Assign directly rather than via updateThresholds(_:), which persists to
        // UserDefaults and would leak these thresholds into every later test.
        store.thresholds = AlarmThresholds(
            urgentLow: 55, low: 70, high: 80, urgentHigh: 250, staleMinutes: 15
        )

        try await store.refresh(scope: .light)

        XCTAssertTrue(
            notifier.posted.contains { $0.identifier.hasPrefix("alarm.") && $0.identifier != "alarm.noData" },
            "a glucose alarm must still be reachable from the light path"
        )
    }

    @MainActor
    func test_lightRefresh_fetchesOnlyEntriesAndDeviceStatus() async throws {
        let client = CountingNightscoutClient()
        let store = AppStore(client: client, alarmEngine: AlarmEngineLive())

        try await store.refresh(scope: .light)

        XCTAssertEqual(client.entriesCalls, 1)
        XCTAssertEqual(client.deviceStatusCalls, 1)
        XCTAssertEqual(client.treatmentsCalls, 0)
        XCTAssertEqual(client.profileCalls, 0)
    }

    @MainActor
    func test_fullRefresh_stillFetchesEverything() async throws {
        let client = CountingNightscoutClient()
        let store = AppStore(client: client, alarmEngine: AlarmEngineLive())

        try await store.refresh(scope: .full)

        XCTAssertEqual(client.entriesCalls, 1)
        XCTAssertEqual(client.deviceStatusCalls, 1)
        XCTAssertEqual(client.treatmentsCalls, 2)
        XCTAssertEqual(client.profileCalls, 1)
    }

    @MainActor
    func test_lightRefresh_mergesIntoExistingReadings_withoutTruncating() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        let old = (1...200).map { i in
            GlucoseReading(
                date: Date(timeIntervalSince1970: 1_700_000_000 - Double(i) * 300),
                mgdl: 100,
                trend: .flat
            )
        }
        store.readings = old

        try await store.refresh(scope: .light)

        XCTAssertGreaterThanOrEqual(store.readings.count, old.count)
    }

    @MainActor
    func test_lightRefresh_deduplicatesByDate() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())

        try await store.refresh(scope: .light)
        let afterFirst = store.readings.count
        try await store.refresh(scope: .light)

        XCTAssertEqual(store.readings.count, afterFirst)
    }

    @MainActor
    func test_lightRefresh_capsReadingsAt288() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        let old = (1...400).map { i in
            GlucoseReading(
                date: Date(timeIntervalSince1970: 1_700_000_000 - Double(i) * 300),
                mgdl: 100,
                trend: .flat
            )
        }
        store.readings = old

        try await store.refresh(scope: .light)

        XCTAssertEqual(store.readings.count, 288)
    }

    @MainActor
    func test_lightRefresh_doesNotSuppressTheNextForegroundFullRefresh() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())

        try await store.refresh(scope: .light)

        XCTAssertTrue(store.isStale)
    }

    @MainActor
    func test_fullRefresh_clearsStaleness() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())

        try await store.refresh(scope: .full)

        XCTAssertFalse(store.isStale)
    }
}
