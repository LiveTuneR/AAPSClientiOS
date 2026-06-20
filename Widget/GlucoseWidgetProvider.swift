import WidgetKit
import Foundation

struct GlucoseTimelineEntry: TimelineEntry {
    let date: Date
    let entry: GlucoseWidgetEntry
}

struct GlucoseTimelineProvider: TimelineProvider {
    private let store = SharedStore()

    func placeholder(in context: Context) -> GlucoseTimelineEntry {
        GlucoseTimelineEntry(date: Date(), entry: fallbackEntry())
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseTimelineEntry) -> Void) {
        completion(GlucoseTimelineEntry(date: Date(), entry: fallbackEntry()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseTimelineEntry>) -> Void) {
        Task {
            let now = Date()
            let config = store.loadConfig()
            let entry = await fetchEntry(config: config, needsLoop: context.family == .systemMedium, now: now)
            let next = now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [GlucoseTimelineEntry(date: now, entry: entry)],
                                policy: .after(next)))
        }
    }

    /// Snapshot from App Group, used as placeholder and as fetch fallback.
    private func fallbackEntry() -> GlucoseWidgetEntry {
        let config = store.loadConfig()
        guard let snap = store.loadSnapshot() else {
            return GlucoseWidgetEntry.noData(units: config.units, now: Date())
        }
        let minutesAgo = max(0, Int(Date().timeIntervalSince(snap.date) / 60))
        return GlucoseWidgetEntry(
            mgdl: snap.mgdl, trend: snap.trend, delta: snap.delta, date: snap.date,
            minutesAgo: minutesAgo, isStale: minutesAgo >= config.thresholds.staleMinutes,
            iob: snap.iob, cob: snap.cob,
            classification: Formatting.classify(mgdl: snap.mgdl, thresholds: config.thresholds),
            units: config.units, state: .data
        )
    }

    private func fetchEntry(config: DisplayConfig, needsLoop: Bool, now: Date) async -> GlucoseWidgetEntry {
        let keychain = KeychainStore(
            service: SharedConstants.keychainService,
            accessGroup: SharedConstants.keychainAccessGroup
        )
        let urlStr = (try? keychain.get(.nsUrl)) ?? nil
        let token = (try? keychain.get(.nsAccessToken)) ?? nil
        guard let urlStr, let url = URL(string: urlStr),
              let token, !token.isEmpty
        else {
            return GlucoseWidgetEntry.noData(units: config.units, now: now)
        }
        let client = NightscoutClientLive(baseURL: url, accessToken: token, transport: URLSessionTransport())
        do {
            try await client.authorize()
            let readings = try await client.fetchEntries(limit: 2)
            let loop: LoopStatus? = needsLoop ? (try? await client.fetchDeviceStatus()) ?? nil : nil
            let entry = WidgetEntryBuilder.build(readings: readings, loop: loop, config: config, now: now)
            return entry.state == .noData ? fallbackEntry() : entry
        } catch {
            return fallbackEntry()
        }
    }
}
