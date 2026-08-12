import SwiftUI
import WidgetKit

struct WatchGlucoseTimelineEntry: TimelineEntry {
    let date: Date
    let payload: WatchGlucosePayload?
}

struct WatchGlucoseTimelineProvider: TimelineProvider {
    private let store = WatchPayloadStore()

    func placeholder(in context: Context) -> WatchGlucoseTimelineEntry {
        WatchGlucoseTimelineEntry(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchGlucoseTimelineEntry) -> Void) {
        completion(WatchGlucoseTimelineEntry(date: Date(), payload: store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchGlucoseTimelineEntry>) -> Void) {
        let now = Date()
        guard let payload = store.load() else {
            completion(Timeline(
                entries: [WatchGlucoseTimelineEntry(date: now, payload: nil)],
                policy: .after(now.addingTimeInterval(15 * 60))
            ))
            return
        }

        var entries = [WatchGlucoseTimelineEntry(date: now, payload: payload)]
        let staleDate = payload.readingDate.addingTimeInterval(Double(payload.staleMinutes * 60))
        if staleDate > now {
            entries.append(WatchGlucoseTimelineEntry(date: staleDate, payload: payload))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct WatchGlucoseComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchGlucoseTimelineEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .accessoryCorner: corner
            default: inline
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(entry.payload?.formattedValue() ?? "--")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text(entry.payload?.trendSymbol ?? "")
                    .font(.caption2).bold()
            }
            .foregroundStyle(WatchGlucoseStyle.color(for: entry.payload, at: entry.date))
        }
    }

    private var rectangular: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.payload?.formattedValue() ?? "--")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(entry.payload?.trendSymbol ?? "").font(.headline).bold()
                Text(entry.payload?.formattedDelta() ?? "").font(.caption).bold()
                Spacer()
                if let payload = entry.payload {
                    Text(payload.readingDate, style: .time).font(.caption2)
                }
            }
            .foregroundStyle(WatchGlucoseStyle.color(for: entry.payload, at: entry.date))
            if let payload = entry.payload {
                WatchGlucoseChart(payload: payload, hours: 3)
            }
        }
    }

    private var inline: some View {
        Text("\(entry.payload?.formattedValue() ?? "--") \(entry.payload?.trendSymbol ?? "") \(entry.payload?.formattedDelta() ?? "")")
    }

    private var corner: some View {
        Text("\(entry.payload?.formattedValue() ?? "--")\(entry.payload?.trendSymbol ?? "")")
            .font(.headline).bold()
            .foregroundStyle(WatchGlucoseStyle.color(for: entry.payload, at: entry.date))
            .widgetLabel {
                Text(entry.payload?.formattedDelta() ?? "")
            }
    }
}

@main
struct AAPSWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AAPSWatchGlucose", provider: WatchGlucoseTimelineProvider()) { entry in
            WatchGlucoseComplicationView(entry: entry)
        }
        .configurationDisplayName("AAPS Glucose")
        .description("Current glucose and recent history")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}
