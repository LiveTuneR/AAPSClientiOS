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

final class AppStore: ObservableObject {
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

    var activeProfileSwitch: Treatment? {
        // Profile switches are infrequent → may be outside the general treatments window.
        // careEvents includes a dedicated "Profile Switch" query, so search there too.
        (careEvents + treatments)
            .filter { $0.eventType == "Profile Switch" }
            .max(by: { $0.date < $1.date })
    }

    /// Active profile name — from latest Profile Switch, else profile store default.
    var activeProfileName: String? {
        activeProfileSwitch?.profileName ?? profileStore?.defaultProfileName
    }

    let alarmEngine: AlarmEngine
    var client: NightscoutClient
    private(set) var lastRefresh = Date.distantPast
    private let sharedStore = SharedStore()

    /// Data older than this is considered stale and worth refetching.
    var isStale: Bool { Date().timeIntervalSince(lastRefresh) > 60 }

    /// Refresh only if cached data is stale — used on view appear / app activation so switching
    /// tabs doesn't refetch. Pull-to-refresh bypasses this by calling refresh() directly.
    func refreshIfStale() async {
        guard isStale else { return }
        try? await refresh()
    }

    init(client: NightscoutClient, alarmEngine: AlarmEngine) {
        self.client = client
        self.alarmEngine = alarmEngine
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
        updateSharedSnapshot()
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

    func refresh() async throws {
        ensureConfigured()
        var firstError: Error?
        var entriesOk = false

        // Assign each piece independently — a partial failure keeps previously loaded data.
        do {
            let r = try await client.fetchEntries(limit: 288)
            await MainActor.run { readings = r }
            entriesOk = true
        } catch is CancellationError { return }
        catch { firstError = firstError ?? RefreshError.stage("entries", error) }

        do {
            let t = try await client.fetchTreatments(since: nil)
            await MainActor.run { treatments = t }
        } catch is CancellationError { return }
        catch { firstError = firstError ?? RefreshError.stage("treatments", error) }

        do {
            let s = try await client.fetchDeviceStatus()
            await MainActor.run { loopStatus = s }
        } catch is CancellationError { return }
        catch { firstError = firstError ?? RefreshError.stage("devicestatus", error) }

        if let p = try? await client.fetchProfile() {
            await MainActor.run { profile = p }
        }

        if let ps = try? await client.fetchProfileStore() {
            await MainActor.run { profileStore = ps }
        }

        if let care = try? await client.fetchCareEvents() {
            await MainActor.run { careEvents = care }
        }

        if let history = try? await client.fetchDeviceStatusHistory(since: Date().addingTimeInterval(-12 * 3600)) {
            await MainActor.run { deviceStatusHistory = history }
        }

        await MainActor.run {
            connectionLost = firstError != nil
            if entriesOk { lastRefresh = Date() }
        }

        evaluateAlarms()

        if let firstError {
            alarmEngine.schedule(.connectionLost)
            throw firstError
        }

        updateSharedSnapshot()
    }

    /// Mirror the latest reading + display config into the App Group for the widget.
    func updateSharedSnapshot() {
        sharedStore.saveConfig(DisplayConfig(units: displayUnits, thresholds: thresholds))
        guard let latest = readings.first else { return }
        let delta = readings.count >= 2 ? latest.mgdl - readings[1].mgdl : nil
        let snap = GlucoseSnapshot(
            mgdl: latest.mgdl, trend: latest.trend, delta: delta, date: latest.date,
            iob: loopStatus?.iob, cob: loopStatus?.cob
        )
        sharedStore.saveSnapshot(snap)
        WidgetCenter.shared.reloadAllTimelines()

        if #available(iOS 16.1, *), let latest = readings.first {
            LiveActivityController.shared.update(
                GlucoseActivityAttributes.ContentState(
                    mgdl: latest.mgdl, trendRaw: latest.trend.rawValue,
                    delta: readings.count >= 2 ? latest.mgdl - readings[1].mgdl : nil,
                    date: latest.date, iob: loopStatus?.iob, unitsRaw: displayUnits.rawValue
                )
            )
        }
    }

    @available(iOS 16.1, *)
    func setLiveActivityEnabled(_ on: Bool) {
        guard on else { LiveActivityController.shared.stop(); return }
        guard let latest = readings.first else { return }
        LiveActivityController.shared.start(
            with: GlucoseActivityAttributes.ContentState(
                mgdl: latest.mgdl, trendRaw: latest.trend.rawValue,
                delta: readings.count >= 2 ? latest.mgdl - readings[1].mgdl : nil,
                date: latest.date, iob: loopStatus?.iob, unitsRaw: displayUnits.rawValue
            )
        )
    }

    private func evaluateAlarms() {
        guard let alarm = alarmEngine.evaluate(
            latest: readings.first,
            lastUpdate: lastRefresh,
            now: Date(),
            thresholds: thresholds
        ) else { return }

        if alarm == .connectionLost {
            return
        }
        alarmEngine.schedule(alarm)
    }
}
