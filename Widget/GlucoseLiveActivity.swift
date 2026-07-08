import WidgetKit
import ActivityKit
import SwiftUI

@available(iOS 16.1, *)
struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(value(context.state)).font(.title2).bold()
                    Text(trend(context.state))
                    Spacer()
                    if let iob = context.state.iob { Text(String(format: "IOB %.1f", iob)).font(.caption) }
                    if let cob = context.state.cob { Text(String(format: "COB %.0f", cob)).font(.caption) }
                    Text(context.state.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                if context.state.tempBasalRate != nil || context.state.activeProfileName != nil {
                    HStack {
                        if let rate = context.state.tempBasalRate { Text(String(format: "Basal %.2f U/h", rate)).font(.caption2) }
                        if let name = context.state.activeProfileName {
                            let pct = context.state.activeProfilePercentage ?? 100
                            Text(pct == 100 ? name : "\(name) (\(pct)%)").font(.caption2)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                }
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            if let d = context.state.delta { Text(delta(d, context.state)) }
                            Spacer()
                            if let iob = context.state.iob { Text(String(format: "IOB %.1f", iob)) }
                            if let cob = context.state.cob { Text(String(format: "COB %.0f", cob)) }
                            Text(context.state.date, style: .relative).foregroundStyle(.secondary)
                        }
                        if context.state.tempBasalRate != nil || context.state.activeProfileName != nil {
                            HStack {
                                if let rate = context.state.tempBasalRate { Text(String(format: "Basal %.2f U/h", rate)) }
                                if let name = context.state.activeProfileName {
                                    let pct = context.state.activeProfilePercentage ?? 100
                                    Text(pct == 100 ? name : "\(name) (\(pct)%)")
                                }
                                Spacer()
                            }
                        }
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
}
