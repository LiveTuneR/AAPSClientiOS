import XCTest
@testable import AAPSClientiOS

final class AppStoreTests: XCTestCase {

    func test_refreshFillsStore() async throws {
        let mockClient = FixtureNightscoutClient()
        let engine = AlarmEngineLive()
        let store = AppStore(client: mockClient, alarmEngine: engine)

        try await store.refresh()

        XCTAssertEqual(store.readings.count, 2)
        XCTAssertEqual(store.loopStatus?.iob, 1.85)
        XCTAssertEqual(store.treatments.count, 4)
    }

    func test_connectionLostAlarmOnNetworkError() async throws {
        let mockClient = FixtureNightscoutClient()
        let notifier = MockNotifier()
        let engine = AlarmEngineLive(notifier: notifier)
        let store = AppStore(client: mockClient, alarmEngine: engine)

        try await store.refresh()

        mockClient.shouldThrow = NsError.noNetwork

        do {
            try await store.refresh()
            XCTFail("Expected error")
        } catch {
        }

        XCTAssertEqual(store.connectionLost, true)
        XCTAssertEqual(notifier.posted.map(\.identifier), ["alarm.connectionLost"])
    }

    func test_staleDataTriggersNoDataAlarm() async throws {
        let mockClient = FixtureNightscoutClient()
        let notifier = MockNotifier()
        let engine = AlarmEngineLive(notifier: notifier)
        let store = AppStore(client: mockClient, alarmEngine: engine)
        store.thresholds = AlarmThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250, staleMinutes: 0)

        try await store.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        let result = await store.alarmEngine.evaluate(
            latest: store.readings.first,
            lastUpdate: store.lastRefresh,
            now: Date(),
            thresholds: store.thresholds
        )
        XCTAssertEqual(result, .noData)
    }

    func test_thresholdsPersistInUserDefaults() async throws {
        let mockClient = FixtureNightscoutClient()
        let engine = AlarmEngineLive()
        let store = AppStore(client: mockClient, alarmEngine: engine)

        let newThresholds = AlarmThresholds(urgentLow: 60, low: 80, high: 200, urgentHigh: 300, staleMinutes: 20)
        store.updateThresholds(newThresholds)

        let d = UserDefaults.standard
        XCTAssertEqual(d.integer(forKey: "threshold.urgentLow"), 60)
        XCTAssertEqual(d.integer(forKey: "threshold.staleMinutes"), 20)
        XCTAssertEqual(store.thresholds, newThresholds)
    }

    func test_thresholdsLoadedFromUserDefaults() {
        let d = UserDefaults.standard
        d.set(65, forKey: "threshold.urgentLow")
        d.set(75, forKey: "threshold.low")
        d.set(185, forKey: "threshold.high")
        d.set(255, forKey: "threshold.urgentHigh")
        d.set(10, forKey: "threshold.staleMinutes")

        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        XCTAssertEqual(store.thresholds.urgentLow, 65)
        XCTAssertEqual(store.thresholds.staleMinutes, 10)

        d.removeObject(forKey: "threshold.urgentLow")
    }

    func test_reconnectUpdatesClientAndRefreshes() async throws {
        let engine = AlarmEngineLive()
        let store = AppStore(client: UnconfiguredTestClient(), alarmEngine: engine)

        do {
            try await store.refresh()
            XCTFail("Expected badURL")
        } catch { }

        let mockClient = FixtureNightscoutClient()
        store.client = mockClient

        try await store.refresh()
        XCTAssertEqual(store.readings.count, 2)
    }

    func test_displayUnitsDefaultToMgdl() {
        UserDefaults.standard.removeObject(forKey: "display.glucoseUnits")
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        XCTAssertEqual(store.displayUnits, .mgdl)
    }

    func test_displayUnitsReadFromUserDefaults() {
        UserDefaults.standard.set("mmol/l", forKey: "display.glucoseUnits")
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        XCTAssertEqual(store.displayUnits, .mmol)
        UserDefaults.standard.removeObject(forKey: "display.glucoseUnits")
    }

    func test_refreshPopulatesDeviceStatusHistory() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        try await store.refresh()
        XCTAssertEqual(store.deviceStatusHistory.count, 5)
        XCTAssertEqual(store.deviceStatusHistory[0].iob, 1.20, accuracy: 0.001)
        XCTAssertEqual(store.deviceStatusHistory[2].cob, 35.0, accuracy: 0.01)
    }
}

private final class UnconfiguredTestClient: NightscoutClient {
    func authorize() async throws { throw NsError.badURL }
    func fetchEntries(limit: Int) async throws -> [GlucoseReading] { throw NsError.badURL }
    func fetchTreatments(since: Date?) async throws -> [Treatment] { throw NsError.badURL }
    func fetchDeviceStatus() async throws -> LoopStatus? { throw NsError.badURL }
    func fetchProfile() async throws -> NsProfile { throw NsError.badURL }
    func fetchProfileStore() async throws -> NsProfileStore { throw NsError.badURL }
    func postTreatment(_ payload: [String: Any]) async throws { throw NsError.badURL }
    func fetchCareEvents() async throws -> [Treatment] { throw NsError.badURL }
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading] { throw NsError.badURL }
    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry] { throw NsError.badURL }
}
