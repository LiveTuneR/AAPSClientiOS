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
