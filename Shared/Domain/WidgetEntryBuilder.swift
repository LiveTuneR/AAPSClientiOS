import Foundation

/// Render-ready data for a widget timeline entry. Pure value type.
struct GlucoseWidgetEntry: Equatable {
    enum State: Equatable { case data, noData }

    let mgdl: Int
    let trend: TrendArrow
    let delta: Int?
    let date: Date
    let minutesAgo: Int
    let isStale: Bool
    let iob: Double?
    let cob: Double?
    let classification: GlucoseClassification
    let units: GlucoseUnits
    let state: State

    /// Placeholder shown when no credentials / no data are available.
    static func noData(units: GlucoseUnits, now: Date) -> GlucoseWidgetEntry {
        GlucoseWidgetEntry(
            mgdl: 0, trend: .none, delta: nil, date: now, minutesAgo: 0,
            isStale: true, iob: nil, cob: nil, classification: .inRange,
            units: units, state: .noData
        )
    }
}

enum WidgetEntryBuilder {
    /// Build an entry from readings sorted newest-first (as NS returns them).
    static func build(
        readings: [GlucoseReading],
        loop: LoopStatus?,
        config: DisplayConfig,
        now: Date
    ) -> GlucoseWidgetEntry {
        guard let latest = readings.first else {
            return .noData(units: config.units, now: now)
        }
        let delta = readings.count >= 2 ? latest.mgdl - readings[1].mgdl : nil
        let minutesAgo = max(0, Int(now.timeIntervalSince(latest.date) / 60))
        let isStale = minutesAgo >= config.thresholds.staleMinutes
        return GlucoseWidgetEntry(
            mgdl: latest.mgdl,
            trend: latest.trend,
            delta: delta,
            date: latest.date,
            minutesAgo: minutesAgo,
            isStale: isStale,
            iob: loop?.iob,
            cob: loop?.cob,
            classification: Formatting.classify(mgdl: latest.mgdl, thresholds: config.thresholds),
            units: config.units,
            state: .data
        )
    }
}
