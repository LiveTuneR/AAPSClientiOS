import WidgetKit
import ActivityKit
import SwiftUI

@available(iOS 16.1, *)
struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            HStack {
                Text(value(context.state)).font(.title2).bold()
                Text(trend(context.state))
                Spacer()
                if let iob = context.state.iob { Text(String(format: "IOB %.1f", iob)).font(.caption) }
                Text(ago(context.state)).font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(value(context.state)).font(.title3).bold()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(trend(context.state))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let d = context.state.delta { Text(delta(d, context.state)) }
                        Spacer()
                        if let iob = context.state.iob { Text(String(format: "IOB %.1f", iob)) }
                        Text(ago(context.state)).foregroundStyle(.secondary)
                    }.font(.caption)
                }
            } compactLeading: {
                Text(value(context.state)).font(.caption).bold()
            } compactTrailing: {
                Text(trend(context.state)).font(.caption)
            } minimal: {
                Text(value(context.state)).font(.caption2)
            }
        }
    }

    private func units(_ s: GlucoseActivityAttributes.ContentState) -> GlucoseUnits {
        GlucoseUnits(rawValue: s.unitsRaw) ?? .mgdl
    }
    private func value(_ s: GlucoseActivityAttributes.ContentState) -> String {
        Formatting.format(s.mgdl, units: units(s))
    }
    private func trend(_ s: GlucoseActivityAttributes.ContentState) -> String {
        Formatting.trendSymbol(TrendArrow(rawValue: s.trendRaw) ?? .none)
    }
    private func delta(_ d: Int, _ s: GlucoseActivityAttributes.ContentState) -> String {
        (d >= 0 ? "+" : "−") + Formatting.format(abs(d), units: units(s))
    }
    private func ago(_ s: GlucoseActivityAttributes.ContentState) -> String {
        "\(max(0, Int(Date().timeIntervalSince(s.date) / 60))) min"
    }
}
