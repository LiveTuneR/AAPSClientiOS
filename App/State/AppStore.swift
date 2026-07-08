import Foundation
import Combine
import WidgetKit

enum RefreshError: LocalizedError {
    case stage(String, Error)
    var errorDescription: String? {
        switch self {
        case .stage(let name, let err):
            return "[\(name)] \(err)"
        }
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var readings: [GlucoseReading] = []
    @Published var treatments: [Treatment] = []
    @Published var loopStatus: LoopStatus?
    @Published var profile: NsProfile?
    @Published var profileStore: NsProfileStore? = nil
    @Published var connectionLost = false
    @Published var thresholds: AlarmThresholds
    @Published var displayUnits: GlucoseUnits = .mgdl
    @Published var careEvents: [Treatment] = []
    @Published var deviceStatusHistory: [DeviceStatusEntry] = []
    @Published var remoteConfigCold: NsRunningConfigCold?
    @Published var remoteConfigHot: NsRunningConfigHot?
    @Published var remoteCapabilities: NsRemoteCapabilities?
    @Published var remoteConfigError: String?

    var activeProfileSwitch: Treatment? {
        (careEvents + treatments)
            .filter { $0.eventType == "Profile Switch" }
            .max(by: { $0.date < $1.date })
    }

    var activeProfileName: String? {
        activeProfileSwitch?.profileName ?? profileStore?.defaultProfileName
    }

    let alarmEngine: AlarmEngine
    private var _client: NightscoutClient
    private let clientLock = NSLock()
    var client: NightscoutClient {
        get { clientLock.lock(); defer { clientLock.unlock() }; return _client }
        set { clientLock.lock(); _client = newValue; clientLock.unlock() }
    }
    private(set) var lastRefresh = Date.distantPast
    private let sharedStore: SharedStore
    private let glucoseNotificationPublisher: GlucoseNotificationPublishing
    private var lastPushedReadingDate: Date?
    private var lastNotifiedReadingDate: Date?
    private var lastLiveActivityReadingDate: Date?
    private var lastLiveActivityPushAt: Date?
    static let liveActivityEnabledKey = "liveActivity.enabled"
    static let liveActivityPushInterval: TimeInterval = 5 * 60
    static let glucoseNotificationEnabledKey = "notification.latestGlucose.enabled"

    var isGlucoseNotificationEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.glucoseNotificationEnabledKey)
    }

    var isLiveActivityEnabled: Bool {
        let isRunning: Bool
        if #available(iOS 16.1, *) {
            isRunning = LiveActivityController.shared.isRunning
        } else {
            isRunning = false
        }
        return Self.resolveLiveActivityPreference(
            defaults: .standard,
            activityIsRunning: isRunning
        )
    }

    static func resolveLiveActivityPreference(
        defaults: UserDefaults,
        activityIsRunning: Bool
    ) -> Bool {
        if defaults.object(forKey: liveActivityEnabledKey) != nil {
            return defaults.bool(forKey: liveActivityEnabledKey)
        }
        if activityIsRunning {
            defaults.set(true, forKey: liveActivityEnabledKey)
        }
        return activityIsRunning
    }

    static func shouldPushLiveActivity(
        readingChanged: Bool,
        activityIsRunning: Bool,
        lastPushAt: Date?,
        now: Date
    ) -> Bool {
        guard activityIsRunning else { return true }
        guard readingChanged else { return false }
        guard let lastPushAt else { return true }
        return now.timeIntervalSince(lastPushAt) >= liveActivityPushInterval
    }

    var ttPresets: [TtReason: TtPreset] {
        get { Self.loadTtPresets() }
        set { Self.saveTtPresets(newValue) }
    }

    var remoteTempTargetPresets: [NsSyncedTempTargetPreset] {
        NsSyncedPrefsParser.tempTargetPresets(from: remoteConfigCold?.syncedPrefsSnapshot.tempTargetPresetsJson)
    }

    var remoteSceneDefinitions: [NsSceneDefinition] {
        NsSyncedPrefsParser.sceneDefinitions(from: remoteConfigCold?.syncedPrefsSnapshot.sceneDefinitionsJson)
    }

    var remoteQuickWizardEntries: [NsQuickWizardEntry] {
        NsSyncedPrefsParser.quickWizardEntries(from: remoteConfigCold?.syncedPrefsSnapshot.quickWizardJson)
    }

    var activeRemoteSceneDefinition: NsSceneDefinition? {
        guard let sceneId = remoteConfigHot?.activeScene?.sceneId else { return nil }
        return remoteSceneDefinitions.first(where: { $0.sceneId == sceneId })
    }

    var activeRemoteSceneDisplayName: String? {
        if let name = activeRemoteSceneDefinition?.name, !name.isEmpty {
            return name
        }
        return remoteConfigHot?.activeScene?.sceneId
    }

    var isStale: Bool { Date().timeIntervalSince(lastRefresh) > 60 }

    func refreshIfStale() async {
        guard isStale else { return }
        try? await refresh()
    }

    func fetchHistory(days: Int) async throws -> [GlucoseReading] {
        ensureConfigured()
        return try await client.fetchEntries(sinceDays: days)
    }

    func fetchTreatmentHistory(days: Int) async throws -> [Treatment] {
        ensureConfigured()
        return try await client.fetchTreatmentsHistory(since: Date().addingTimeInterval(-Double(days) * 86400))
    }

    init(
        client: NightscoutClient,
        alarmEngine: AlarmEngine,
        sharedStore: SharedStore = SharedStore(),
        glucoseNotificationPublisher: GlucoseNotificationPublishing = DummyGlucoseNotificationPublisher()
    ) {
        self._client = client
        self.alarmEngine = alarmEngine
        self.sharedStore = sharedStore
        self.glucoseNotificationPublisher = glucoseNotificationPublisher
        self.thresholds = Self.loadThresholds()
        self.displayUnits = Self.loadDisplayUnits()
        ensureConfigured()
    }

    func reconnect(baseURL: URL, accessToken: String) {
        client = NightscoutClientLive(baseURL: baseURL, accessToken: accessToken, transport: URLSessionTransport())
    }

    /// Normalize user-entered NS URL: trim, add https:// if scheme missing.
    static func normalizedURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        return URL(string: s)
    }

    /// Rebuild a live client from Keychain if the current one isn't configured.
    /// Makes refresh resilient to launch timing / Keychain re-population.
    func ensureConfigured() {
        guard !(client is NightscoutClientLive) else { return }
        let kc = SharedConstants.credentialKeychain()
        let urlStr = (try? kc.get(.nsUrl)) ?? nil
        let token = (try? kc.get(.nsAccessToken)) ?? nil
        guard let urlStr, let url = Self.normalizedURL(urlStr),
              let token, !token.isEmpty else { return }
        client = NightscoutClientLive(baseURL: url, accessToken: token, transport: URLSessionTransport())
    }

    func setDisplayUnits(_ units: GlucoseUnits) {
        displayUnits = units
        UserDefaults.standard.set(units.rawValue, forKey: "display.glucoseUnits")
        // Force a push: the reading is unchanged but the rendered units differ.
        updateSharedSnapshot(force: true)
    }

    private static func loadDisplayUnits() -> GlucoseUnits {
        let raw = UserDefaults.standard.string(forKey: "display.glucoseUnits") ?? ""
        return GlucoseUnits(rawValue: raw) ?? .mgdl
    }

    func updateThresholds(_ t: AlarmThresholds) {
        thresholds = t
        let d = UserDefaults.standard
        d.set(t.urgentLow, forKey: "threshold.urgentLow")
        d.set(t.low, forKey: "threshold.low")
        d.set(t.high, forKey: "threshold.high")
        d.set(t.urgentHigh, forKey: "threshold.urgentHigh")
        d.set(t.staleMinutes, forKey: "threshold.staleMinutes")
    }

    private static func loadThresholds() -> AlarmThresholds {
        let d = UserDefaults.standard
        if d.object(forKey: "threshold.urgentLow") == nil { return .defaults }
        return AlarmThresholds(
            urgentLow: d.integer(forKey: "threshold.urgentLow"),
            low: d.integer(forKey: "threshold.low"),
            high: d.integer(forKey: "threshold.high"),
            urgentHigh: d.integer(forKey: "threshold.urgentHigh"),
            staleMinutes: d.integer(forKey: "threshold.staleMinutes")
        )
    }

    private static func loadTtPresets() -> [TtReason: TtPreset] {
        let d = UserDefaults.standard
        var presets: [TtReason: TtPreset] = [:]
        for reason in [TtReason.eatingSoon, .activity, .hypo] {
            let key = "ttPreset.\(reason.rawValue)"
            if let data = d.data(forKey: key),
               let preset = try? JSONDecoder().decode(TtPreset.self, from: data) {
                presets[reason] = preset
            } else {
                presets[reason] = TtPreset(targetMgdl: reason.defaultTargetMgdl,
                                           durationMin: reason.defaultDurationMin)
            }
        }
        return presets
    }

    private static func saveTtPresets(_ presets: [TtReason: TtPreset]) {
        let d = UserDefaults.standard
        for (reason, preset) in presets {
            let key = "ttPreset.\(reason.rawValue)"
            if let data = try? JSONEncoder().encode(preset) {
                d.set(data, forKey: key)
            }
        }
    }

    func refresh() async throws {
        ensureConfigured()
        var firstError: Error?
        var entriesOk = false

        defer { if entriesOk { updateSharedSnapshot() } }

        // Assign each piece independently — a partial failure keeps previously loaded data.
        do {
            let r = try await client.fetchEntries(limit: 288)
            readings = r
            entriesOk = true
        } catch is CancellationError { return }
        catch { firstError = firstError ?? RefreshError.stage("entries", error) }

        do {
            let t = try await client.fetchTreatments(since: nil)
            treatments = t
        } catch is CancellationError { return }
        catch { firstError = firstError ?? RefreshError.stage("treatments", error) }

        do {
            let s = try await client.fetchDeviceStatus()
            loopStatus = s
        } catch is CancellationError { return }
        catch { firstError = firstError ?? RefreshError.stage("devicestatus", error) }

        if let p = try? await client.fetchProfile() {
            profile = p
        }

        if let ps = try? await client.fetchProfileStore() {
            profileStore = ps
        }

        if let care = try? await client.fetchCareEvents() {
            careEvents = care
        }

        if let history = try? await client.fetchDeviceStatusHistory(since: Date().addingTimeInterval(-12 * 3600)) {
            deviceStatusHistory = history
        }

        remoteConfigError = nil
        do {
            let cold = try await client.fetchRunningConfigCold()
            remoteConfigCold = cold
            remoteCapabilities = cold?.remoteCapabilities
        } catch is CancellationError { return }
        catch {
            rememberRemoteConfigError(error)
        }

        do {
            remoteConfigHot = try await client.fetchRunningConfigHot()
        } catch is CancellationError { return }
        catch {
            rememberRemoteConfigError(error)
        }

        connectionLost = firstError != nil
        if entriesOk {
            lastRefresh = Date()
        }

        if let reading = readings.first,
           let alarm = alarmEngine.evaluate(
               latest: reading,
               lastUpdate: lastRefresh,
               now: Date(),
               thresholds: thresholds
           ), alarm != .connectionLost {
            alarmEngine.schedule(alarm)
        }

        // Snapshot mirroring runs via the `defer` above on every exit path.
        if let firstError {
            alarmEngine.schedule(.connectionLost)
            throw firstError
        }
    }

    /// Mirror the latest reading + display config into the App Group for the widget.
    ///
    /// The snapshot is always persisted so the widget's timeline provider reads the
    /// freshest data whenever the system next asks for it.
    ///
    /// Widget reload fires only when the reading actually changed (or `force`) to
    /// stay under the timeline reload budget.
    ///
    /// Live Activity update fires on EVERY call. With `NSSupportsLiveActivitiesFrequentUpdates`
    /// the budget is generous (~70/hour). Pushing every 60 s keeps staleDate fresh so
    /// the countdown timer never drifts, and if ActivityKit drops an update the next
    /// poll recovers within 60 s instead of accumulating drift.
    func updateSharedSnapshot(force: Bool = false) {
        sharedStore.saveConfig(DisplayConfig(units: displayUnits, thresholds: thresholds))
        var readingChanged = force
        if let latest = readings.first {
            let delta = readings.count >= 2 ? latest.mgdl - readings[1].mgdl : nil
            let snap = GlucoseSnapshot(
                mgdl: latest.mgdl, trend: latest.trend, delta: delta, date: latest.date,
                iob: loopStatus?.iob, cob: loopStatus?.cob,
                tempBasalRate: loopStatus?.tempBasalRate,
                activeProfileName: activeProfileName,
                activeProfilePercentage: activeProfileSwitch?.percentage
            )
            sharedStore.saveSnapshot(snap)

            readingChanged = force || latest.date != lastPushedReadingDate
            if readingChanged {
                lastPushedReadingDate = latest.date
                WidgetCenter.shared.reloadAllTimelines()
            }

            updateGlucoseNotification(force: force)
        }

        if #available(iOS 16.1, *), !readings.isEmpty, isLiveActivityEnabled {
            let activityIsRunning = LiveActivityController.shared.isRunning
            let latestDate = readings[0].date
            let liveActivityReadingChanged = force || latestDate != lastLiveActivityReadingDate
            let now = Date()
            if Self.shouldPushLiveActivity(
                readingChanged: liveActivityReadingChanged,
                activityIsRunning: activityIsRunning,
                lastPushAt: lastLiveActivityPushAt,
                now: now
            ), LiveActivityController.shared.startOrUpdate(with: makeLAContentState()) {
                lastLiveActivityReadingDate = latestDate
                lastLiveActivityPushAt = now
            }
        }
    }

    func setGlucoseNotificationEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.glucoseNotificationEnabledKey)
        guard on else {
            glucoseNotificationPublisher.remove()
            lastNotifiedReadingDate = nil
            return
        }
        updateGlucoseNotification(force: true)
    }

    private func updateGlucoseNotification(force: Bool) {
        guard isGlucoseNotificationEnabled,
              let latest = readings.first,
              force || latest.date != lastNotifiedReadingDate else { return }
        let timeText = latest.date.formatted(date: .omitted, time: .shortened)
        glucoseNotificationPublisher.replace(with: GlucoseNotificationController.content(
            latest: latest,
            previous: readings.dropFirst().first,
            units: displayUnits,
            timeText: timeText
        ))
        lastNotifiedReadingDate = latest.date
    }

    @available(iOS 16.1, *)
    func setLiveActivityEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.liveActivityEnabledKey)
        guard on else { LiveActivityController.shared.stop(); return }
        guard let latest = readings.first else { return }
        if LiveActivityController.shared.startOrUpdate(with: makeLAContentState()) {
            lastLiveActivityReadingDate = latest.date
            lastLiveActivityPushAt = Date()
        }
    }

    @available(iOS 16.1, *)
    private func makeLAContentState() -> GlucoseActivityAttributes.ContentState {
        let latest = readings[0]
        let delta = readings.count >= 2 ? latest.mgdl - readings[1].mgdl : nil
        return GlucoseActivityAttributes.ContentState(
            mgdl: latest.mgdl, trendRaw: latest.trend.rawValue,
            delta: delta,
            date: latest.date, iob: loopStatus?.iob, unitsRaw: displayUnits.rawValue,
            cob: loopStatus?.cob,
            tempBasalRate: loopStatus?.tempBasalRate,
            activeProfileName: activeProfileName,
            activeProfilePercentage: activeProfileSwitch?.percentage
        )
    }

    private func rememberRemoteConfigError(_ error: Error) {
        if remoteConfigError == nil {
            remoteConfigError = error.localizedDescription
        }
    }

}
