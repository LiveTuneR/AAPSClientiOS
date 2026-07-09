import XCTest
@testable import AAPSClientiOS

@MainActor
final class AppStoreTests: XCTestCase {
    func test_liveActivityPreference_migratesRunningActivity() {
        let suite = "AppStoreTests.liveActivityMigration"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        XCTAssertTrue(AppStore.resolveLiveActivityPreference(defaults: defaults, activityIsRunning: true))
        XCTAssertTrue(defaults.bool(forKey: AppStore.liveActivityEnabledKey))

        defaults.removePersistentDomain(forName: suite)
    }

    func test_liveActivityPreference_preservesExplicitOff() {
        let suite = "AppStoreTests.liveActivityExplicitOff"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: AppStore.liveActivityEnabledKey)

        XCTAssertFalse(AppStore.resolveLiveActivityPreference(defaults: defaults, activityIsRunning: true))

        defaults.removePersistentDomain(forName: suite)
    }

    func test_liveActivityStaleDate_isBasedOnReadingTimestamp() {
        let readingDate = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(liveActivityStaleDate(for: readingDate), readingDate.addingTimeInterval(15 * 60))
    }

    func test_liveActivityPush_skipsUnchangedReadingWhileRunning() {
        XCTAssertFalse(AppStore.shouldPushLiveActivity(
            readingChanged: false,
            activityIsRunning: true,
            lastPushAt: nil,
            now: Date()
        ))
    }

    func test_liveActivityPush_coalescesChangedReadingsForFiveMinutes() {
        let lastPush = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(AppStore.shouldPushLiveActivity(
            readingChanged: true,
            activityIsRunning: true,
            lastPushAt: lastPush,
            now: lastPush.addingTimeInterval(299)
        ))
        XCTAssertTrue(AppStore.shouldPushLiveActivity(
            readingChanged: true,
            activityIsRunning: true,
            lastPushAt: lastPush,
            now: lastPush.addingTimeInterval(300)
        ))
    }

    func test_liveActivityPush_sendsFirstReadingOrRestartsMissingActivity() {
        let now = Date()
        XCTAssertTrue(AppStore.shouldPushLiveActivity(
            readingChanged: true,
            activityIsRunning: true,
            lastPushAt: nil,
            now: now
        ))
        XCTAssertTrue(AppStore.shouldPushLiveActivity(
            readingChanged: false,
            activityIsRunning: false,
            lastPushAt: now,
            now: now
        ))
    }

    func test_refreshFillsStore() async throws {
        let mockClient = FixtureNightscoutClient()
        let engine = AlarmEngineLive()
        let store = AppStore(client: mockClient, alarmEngine: engine)

        try await store.refresh()

        XCTAssertEqual(store.readings.count, 2)
        XCTAssertEqual(store.loopStatus?.iob, 1.85)
        XCTAssertEqual(store.treatments.count, 4)
    }

    func test_fetchTreatmentHistoryDelegatesToClient() async throws {
        let mockClient = FixtureNightscoutClient()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive())

        let treatments = try await store.fetchTreatmentHistory(days: 7)

        XCTAssertEqual(treatments.count, 4)
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

    // Regression: a Task cancelled after entries succeed (SwiftUI .task on view
    // disappear, overlapping foreground polls) must still mirror the fresh reading
    // to the App Group + Live Activity. Previously refresh() returned on the
    // CancellationError before updateSharedSnapshot(), freezing the widget/LA while
    // the in-app screen showed new glucose.
    func test_cancellationAfterEntries_stillMirrorsSnapshot() async throws {
        let suiteName = "AppStoreTests.snapshot"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let shared = SharedStore(defaults: defaults)

        let client = FixtureNightscoutClient()
        client.cancelAfterEntries = true
        let store = AppStore(client: client, alarmEngine: AlarmEngineLive(), sharedStore: shared)

        try await store.refresh()  // returns early on the cancelled treatments stage

        XCTAssertFalse(store.readings.isEmpty, "entries should have applied before cancellation")
        let snap = shared.loadSnapshot()
        XCTAssertNotNil(snap, "snapshot must be mirrored even when a later stage cancels")
        XCTAssertEqual(snap?.mgdl, store.readings.first?.mgdl)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_refreshPopulatesDeviceStatusHistory() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
        try await store.refresh()
        XCTAssertEqual(store.deviceStatusHistory.count, 5)
        XCTAssertEqual(store.deviceStatusHistory[0].iob, 1.20, accuracy: 0.001)
        XCTAssertEqual(store.deviceStatusHistory[2].cob, 35.0, accuracy: 0.01)
    }

    func test_refreshLoadsRemoteRunningConfig() async throws {
        let client = FixtureNightscoutClient()
        let store = AppStore(client: client, alarmEngine: AlarmEngineLive())

        try await store.refresh()

        XCTAssertEqual(store.remoteConfigCold?.pump, "Dana-i")
        XCTAssertEqual(store.remoteConfigHot?.activeScene?.sceneId, "school-sport")
        XCTAssertTrue(store.remoteCapabilities?.canRemoteCarbs == true)
        XCTAssertNil(store.remoteConfigError)
    }

    func test_refreshKeepsMainDataWhenRemoteConfigIsInvalid() async throws {
        let client = FixtureNightscoutClient()
        client.settingsByIdentifier[NightscoutSettingsIdentifier.cold] = "settings_invalid"
        let store = AppStore(client: client, alarmEngine: AlarmEngineLive())

        try await store.refresh()

        XCTAssertEqual(store.readings.count, 2)
        XCTAssertNil(store.remoteConfigCold)
        XCTAssertEqual(store.remoteConfigHot?.activeScene?.sceneId, "school-sport")
        XCTAssertNotNil(store.remoteConfigError)
        XCTAssertFalse(store.connectionLost)
    }

    func test_refreshParsesRemoteSyncedPrefs() async throws {
        let store = AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())

        try await store.refresh()

        XCTAssertEqual(store.remoteTempTargetPresets.count, 1)
        XCTAssertEqual(store.remoteTempTargetPresets.first?.name, "Eating Soon")
        XCTAssertEqual(store.remoteTempTargetPresets.first?.targetMgdl, 90)
        XCTAssertEqual(store.remoteSceneDefinitions.first?.sceneId, "school-sport")
        XCTAssertEqual(store.remoteQuickWizardEntries.first?.name, "Breakfast")
        XCTAssertEqual(store.activeRemoteSceneDisplayName, "School Sport")
    }

    func test_refreshRelaysFreshAnnouncement() async throws {
        let mockClient = FixtureNightscoutClient()
        mockClient.treatmentsOverride = [
            Treatment(
                id: "ann1", eventType: "Announcement", date: Date(),
                insulin: nil, carbs: nil, durationMin: nil, enteredBy: nil, notes: "Check pump",
                targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
                absolute: nil, tempBasalPercent: nil
            )
        ]
        let notifier = MockNotifier()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive(), notifier: notifier)

        try await store.refresh()

        XCTAssertEqual(notifier.posted.map(\.body), ["Check pump"])
    }

    func test_refreshDoesNotReRelaySameAnnouncement() async throws {
        let mockClient = FixtureNightscoutClient()
        mockClient.treatmentsOverride = [
            Treatment(
                id: "ann1", eventType: "Announcement", date: Date(),
                insulin: nil, carbs: nil, durationMin: nil, enteredBy: nil, notes: "Check pump",
                targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
                absolute: nil, tempBasalPercent: nil
            )
        ]
        let notifier = MockNotifier()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive(), notifier: notifier)

        try await store.refresh()
        try await store.refresh()

        XCTAssertEqual(notifier.posted.count, 1)
    }

    func test_consumableThresholdsPersistInUserDefaults() async throws {
        let mockClient = FixtureNightscoutClient()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive())

        let custom = ConsumableThresholds(
            cageWarnHours: 40, cageCriticalHours: 60,
            iageWarnHours: 60, iageCriticalHours: 120,
            sageWarnHours: 200, sageCriticalHours: 220,
            bageWarnHours: 200, bageCriticalHours: 220,
            reservoirWarnUnits: 50, reservoirCriticalUnits: 5,
            pumpBattWarnPercent: 40, pumpBattCriticalPercent: 20
        )
        store.updateConsumableThresholds(custom)

        let d = UserDefaults.standard
        XCTAssertEqual(d.integer(forKey: "consumable.cageWarnHours"), 40)
        XCTAssertEqual(d.integer(forKey: "consumable.reservoirCriticalUnits"), 5)
        XCTAssertEqual(store.consumableThresholds, custom)
    }

    func test_consumableThresholdsDefaultWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: "consumable.cageWarnHours")
        let mockClient = FixtureNightscoutClient()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive())
        XCTAssertEqual(store.consumableThresholds, .defaults)
    }

    func test_refreshSchedulesPredictedLowAlarm() async throws {
        let mockClient = FixtureNightscoutClient()
        mockClient.loopStatusOverride = LoopStatus(
            iob: 1.0, cob: 5, eventualBgMgdl: 90, tempBasalRate: 0.5,
            suggestedReason: nil, timestamp: Date(), predictions: nil,
            pumpBattery: 80, pumpReservoir: 100,
            uploaderBattery: 90,
            reason: LoopReason(isfMgdl: nil, cr: nil, targetMgdl: nil, tdd: nil, deviation: nil, bgi: nil, minPredBg: 55, iobPredBg: nil, cobPredBg: nil)
        )
        let notifier = MockNotifier()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive(notifier: notifier))

        try await store.refresh()

        XCTAssertTrue(notifier.posted.map(\.identifier).contains("alarm.predictedLow"))
    }

    func test_refreshDoesNotScheduleWhenPredictionAboveThreshold() async throws {
        let mockClient = FixtureNightscoutClient()
        mockClient.loopStatusOverride = LoopStatus(
            iob: 1.0, cob: 5, eventualBgMgdl: 120, tempBasalRate: 0.5,
            suggestedReason: nil, timestamp: Date(), predictions: nil,
            pumpBattery: 80, pumpReservoir: 100,
            uploaderBattery: 90,
            reason: LoopReason(isfMgdl: nil, cr: nil, targetMgdl: nil, tdd: nil, deviation: nil, bgi: nil, minPredBg: 130, iobPredBg: nil, cobPredBg: nil)
        )
        let notifier = MockNotifier()
        let store = AppStore(client: mockClient, alarmEngine: AlarmEngineLive(notifier: notifier))

        try await store.refresh()

        XCTAssertFalse(notifier.posted.map(\.identifier).contains("alarm.predictedLow"))
    }
}

private final class UnconfiguredTestClient: NightscoutClient {
    func authorize() async throws { throw NsError.badURL }
    func fetchEntries(limit: Int) async throws -> [GlucoseReading] { throw NsError.badURL }
    func fetchTreatments(since: Date?) async throws -> [Treatment] { throw NsError.badURL }
    func fetchDeviceStatus() async throws -> LoopStatus? { throw NsError.badURL }
    func fetchProfile() async throws -> NsProfile { throw NsError.badURL }
    func fetchProfileStore() async throws -> NsProfileStore { throw NsError.badURL }
    func fetchSettings(identifier: String) async throws -> NsSettingsDocument? { throw NsError.badURL }
    func fetchRunningConfigCold() async throws -> NsRunningConfigCold? { throw NsError.badURL }
    func fetchRunningConfigHot() async throws -> NsRunningConfigHot? { throw NsError.badURL }
    func postTreatment(_ payload: [String: Any]) async throws { throw NsError.badURL }
    func fetchCareEvents() async throws -> [Treatment] { throw NsError.badURL }
    func fetchEntries(sinceDays days: Int) async throws -> [GlucoseReading] { throw NsError.badURL }
    func fetchDeviceStatusHistory(since: Date) async throws -> [DeviceStatusEntry] { throw NsError.badURL }
    func fetchTreatmentsHistory(since: Date) async throws -> [Treatment] { throw NsError.badURL }
}
