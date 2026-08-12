import XCTest
@testable import AAPSClientiOS

final class SharedStoreTests: XCTestCase {
    func test_alarmThresholds_codableRoundTrip() throws {
        let original = AlarmThresholds.defaults
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlarmThresholds.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    private func makeStore() -> SharedStore {
        let suite = "test.suite.\(UUID().uuidString)"
        return SharedStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func test_snapshot_roundTrip() {
        let store = makeStore()
        let snap = GlucoseSnapshot(
            mgdl: 120, trend: .flat, delta: 3,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            iob: 1.2, cob: 18
        )
        store.saveSnapshot(snap)
        XCTAssertEqual(store.loadSnapshot(), snap)
    }

    func test_snapshot_emptyByDefault() {
        XCTAssertNil(makeStore().loadSnapshot())
    }

    func test_snapshot_decodesLegacyDataWithoutHistory() throws {
        let json = #"{"mgdl":120,"trend":"flat","delta":2,"date":0,"iob":1.2,"cob":10}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(GlucoseSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.mgdl, 120)
        XCTAssertEqual(snapshot.history, [])
    }

    func test_watchPayloadCarriesHistoryAndStaleness() {
        let readingDate = Date(timeIntervalSince1970: 1_000)
        let snapshot = GlucoseSnapshot(
            mgdl: 123, trend: .fortyFiveUp, delta: 3, date: readingDate,
            iob: 1.2, cob: 10,
            history: [GlucoseSample(mgdl: 120, date: readingDate.addingTimeInterval(-300))]
        )
        let config = DisplayConfig(
            units: .mmol,
            thresholds: AlarmThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250, staleMinutes: 15)
        )
        let payload = WatchGlucosePayload(snapshot: snapshot, config: config, now: readingDate)
        XCTAssertEqual(payload.history.count, 1)
        XCTAssertEqual(payload.trendSymbol, "↗")
        XCTAssertFalse(payload.isStale(at: readingDate.addingTimeInterval(899)))
        XCTAssertTrue(payload.isStale(at: readingDate.addingTimeInterval(900)))
    }

    func test_config_roundTrip() {
        let store = makeStore()
        let config = DisplayConfig(units: .mmol, thresholds: .defaults)
        store.saveConfig(config)
        XCTAssertEqual(store.loadConfig(), config)
    }

    func test_config_defaultsWhenEmpty() {
        XCTAssertEqual(makeStore().loadConfig(), DisplayConfig(units: .mgdl, thresholds: .defaults))
    }
}
