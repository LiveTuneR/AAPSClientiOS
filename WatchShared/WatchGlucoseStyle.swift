import SwiftUI

enum WatchGlucoseStyle {
    static func color(for payload: WatchGlucosePayload?, at date: Date = Date()) -> Color {
        guard let payload else { return .secondary }
        if payload.isStale(at: date) { return .orange }
        if payload.mgdl < payload.low || payload.mgdl >= payload.urgentHigh { return .red }
        if payload.mgdl >= payload.high { return .yellow }
        return .green
    }

    static func unit(for payload: WatchGlucosePayload) -> String {
        payload.unitsRaw.lowercased().contains("mmol") ? "mmol/L" : "mg/dL"
    }
}

struct WatchGlucoseChart: View {
    let payload: WatchGlucosePayload
    var hours: Double = 3

    private var samples: [WatchGlucoseSample] {
        let cutoff = Date().addingTimeInterval(-hours * 3_600).timeIntervalSince1970 * 1_000
        return payload.history
            .filter { Double($0.timestamp) >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        GeometryReader { proxy in
            let values = samples
            let minValue = min(Double(payload.low - 20), Double(values.map(\.mgdl).min() ?? payload.low))
            let maxValue = max(Double(payload.high + 20), Double(values.map(\.mgdl).max() ?? payload.high))
            ZStack {
                thresholdLine(value: Double(payload.low), minValue: minValue, maxValue: maxValue, size: proxy.size)
                    .stroke(.red.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                thresholdLine(value: Double(payload.high), minValue: minValue, maxValue: maxValue, size: proxy.size)
                    .stroke(.yellow.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                chartPath(values: values, minValue: minValue, maxValue: maxValue, size: proxy.size)
                    .stroke(WatchGlucoseStyle.color(for: payload), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityLabel("Glucose history")
    }

    private func chartPath(
        values: [WatchGlucoseSample], minValue: Double, maxValue: Double, size: CGSize
    ) -> Path {
        guard values.count > 1,
              let first = values.first,
              let last = values.last,
              last.timestamp > first.timestamp else { return Path() }
        let valueRange = max(1, maxValue - minValue)
        let timeRange = Double(last.timestamp - first.timestamp)
        var path = Path()
        for (index, sample) in values.enumerated() {
            let x = Double(sample.timestamp - first.timestamp) / timeRange * size.width
            let y = size.height - ((Double(sample.mgdl) - minValue) / valueRange * size.height)
            let point = CGPoint(x: x, y: min(max(0, y), size.height))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func thresholdLine(value: Double, minValue: Double, maxValue: Double, size: CGSize) -> Path {
        let y = size.height - ((value - minValue) / max(1, maxValue - minValue) * size.height)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        return path
    }
}
