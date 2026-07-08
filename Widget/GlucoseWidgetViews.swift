import WidgetKit
import SwiftUI

private func color(for c: GlucoseClassification) -> Color {
    switch c {
    case .urgentLow, .urgentHigh: return .red
    case .low, .high: return .yellow
    case .inRange: return .green
    }
}

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlucoseTimelineEntry

    private var backgroundColor: Color {
        (family == .systemSmall || family == .systemMedium) ? Color(.systemBackground) : .clear
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry.entry)
            case .systemMedium: MediumView(entry: entry.entry)
            case .accessoryCircular: CircularView(entry: entry.entry)
            case .accessoryRectangular: RectangularView(entry: entry.entry)
            case .accessoryInline: InlineView(entry: entry.entry)
            default: SmallView(entry: entry.entry)
            }
        }
        .widgetContainerBackground(backgroundColor)
    }
}

private extension View {
    /// iOS 17 requires widgets to adopt `containerBackground`; on iOS 16 fall back
    /// to a plain background so the same views build and render on both.
    @ViewBuilder
    func widgetContainerBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

private func valueText(_ e: GlucoseWidgetEntry) -> String {
    e.state == .noData ? "--" : Formatting.format(e.mgdl, units: e.units)
}
private func deltaText(_ e: GlucoseWidgetEntry) -> String {
    guard let d = e.delta else { return "" }
    let s = Formatting.format(abs(d), units: e.units)
    return (d >= 0 ? "+" : "−") + s
}

private struct SmallView: View {
    let entry: GlucoseWidgetEntry
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(valueText(entry)).font(.system(size: 36, weight: .bold))
                Text(Formatting.trendSymbol(entry.trend)).font(.title2)
            }
            .foregroundStyle(entry.state == .noData ? Color.secondary : color(for: entry.classification))
            Text(deltaText(entry)).font(.caption).foregroundStyle(.secondary)
            Text(entry.state == .noData ? "No data" : "\(entry.minutesAgo) min ago")
                .font(.caption2)
                .foregroundStyle(entry.isStale ? .orange : .secondary)
        }
    }
}

private struct MediumView: View {
    let entry: GlucoseWidgetEntry
    var body: some View {
        HStack {
            SmallView(entry: entry)
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                if let iob = entry.iob { Text(String(format: "IOB %.1f U", iob)).font(.caption) }
                if let cob = entry.cob { Text(String(format: "COB %.0f g", cob)).font(.caption) }
                if let rate = entry.tempBasalRate { Text(String(format: "Basal %.2f U/h", rate)).font(.caption) }
                if let name = entry.activeProfileName {
                    let pct = entry.activeProfilePercentage ?? 100
                    Text(pct == 100 ? name : "\(name) (\(pct)%)").font(.caption).lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct CircularView: View {
    let entry: GlucoseWidgetEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(valueText(entry)).font(.headline)
                Text(Formatting.trendSymbol(entry.trend)).font(.caption2)
            }
        }
    }
}

private struct RectangularView: View {
    let entry: GlucoseWidgetEntry
    var body: some View {
        HStack {
            Text(valueText(entry)).font(.title3).bold()
            Text(Formatting.trendSymbol(entry.trend))
            Spacer()
            VStack(alignment: .trailing) {
                Text(deltaText(entry)).font(.caption)
                Text("\(entry.minutesAgo)m").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct InlineView: View {
    let entry: GlucoseWidgetEntry
    var body: some View {
        Text("\(valueText(entry)) \(Formatting.trendSymbol(entry.trend)) \(deltaText(entry))")
    }
}
