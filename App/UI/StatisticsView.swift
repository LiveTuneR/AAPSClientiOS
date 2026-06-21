import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var store: AppStore

    @State private var period = 1
    @State private var loaded: [GlucoseReading] = []
    @State private var loading = false

    private var units: GlucoseUnits { store.displayUnits }

    private var stats: GlucoseStats {
        StatisticsCompute.stats(readings: loaded, thresholds: store.thresholds)
    }

    private var agpData: [HourlyPercentiles] {
        StatisticsCompute.hourlyPercentiles(readings: loaded, units: units)
    }

    private func yVal(_ mgdl: Double) -> Double { units == .mmol ? mgdl / 18.0182 : mgdl }
    private var yDomain: ClosedRange<Double> { units == .mmol ? (40/18.0182)...(300/18.0182) : 40...300 }

    var body: some View {
        List {
            Picker("Period", selection: $period) {
                Text("24h").tag(1)
                Text("7d").tag(7)
                Text("30d").tag(30)
                Text("90d").tag(90)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section("Glucose") {
                if loading && loaded.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if period == 1 {
                    glucoseChart
                } else {
                    agpChart
                }
            }

            Section("Time in Range") {
                tirPieChart
                HStack {
                    tirPill("Urg Low", stats.tirBelowUrgent, .red)
                    tirPill("Low", stats.tirBelow, .yellow)
                    tirPill("In Range", stats.tirInRange, .green)
                    tirPill("High", stats.tirAbove, .yellow)
                    tirPill("Urg High", stats.tirAboveUrgent, .red)
                }
                .font(.caption2)
            }

            Section("Metrics") {
                metricRow("Readings", "\(stats.count)")
                metricRow("Mean", Formatting.format(Int(stats.averageMgdl.rounded()), units: units))
                metricRow("GMI (eA1c)", String(format: "%.1f%%", stats.gmiPercent))
                metricRow("CV", String(format: "%.1f%%", stats.cvPercent))
                metricRow("SD", Formatting.format(Int(stats.sdMgdl.rounded()), units: units))
            }
        }
        .navigationTitle("Statistics")
        .task(id: period) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        store.ensureConfigured()
        if let data = try? await store.client.fetchEntries(sinceDays: period) {
            loaded = data
        }
    }

    private var glucoseChart: some View {
        Chart {
            ForEach(loaded) { r in
                PointMark(x: .value("T", r.date), y: .value("G", yVal(Double(r.mgdl))))
                    .foregroundStyle(color(for: Formatting.classify(mgdl: r.mgdl, thresholds: store.thresholds)))
                    .symbolSize(period == 1 ? 12 : 4)
            }
            RuleMark(y: .value("L", yVal(Double(store.thresholds.low))))
                .foregroundStyle(.green.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            RuleMark(y: .value("H", yVal(Double(store.thresholds.high))))
                .foregroundStyle(.green.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
        .chartYScale(domain: yDomain)
        .frame(height: 200)
    }

    // AGP band colors (match AAPS): outer P10–P90 darker steel blue, inner P25–P75 lighter sky blue.
    private let agpOuter = Color(red: 0.17, green: 0.40, blue: 0.66)
    private let agpInner = Color(red: 0.40, green: 0.67, blue: 0.92)

    private var agpLegend: some View {
        HStack(spacing: 14) {
            Text("10%/90%").foregroundColor(agpOuter)
            Text("25%/75%").foregroundColor(agpInner)
            Text("50% (median)").foregroundColor(.primary)
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private var agpYTicks: [(value: Double, label: String)] {
        if units == .mmol {
            return [5, 10, 15].map { (Double($0), "\($0)") }
        } else {
            return [50, 100, 150, 200, 250, 300].map { (Double($0), "\($0)") }
        }
    }

    private var agpChart: some View {
        VStack(spacing: 8) {
            agpLegend
            AGPChartView(
                data: agpData,
                yDomain: yDomain,
                highLine: yVal(Double(store.thresholds.high)),
                lowLine: yVal(Double(store.thresholds.low)),
                yTicks: agpYTicks,
                outer: agpOuter,
                inner: agpInner
            )
            .frame(height: 240)
        }
    }

    private var tirPieChart: some View {
        let segments: [(String, Double, Color)] = [
            ("Urg Low", stats.tirBelowUrgent, .red),
            ("Low", stats.tirBelow, .yellow),
            ("In Range", stats.tirInRange, .green),
            ("High", stats.tirAbove, .yellow),
            ("Urg High", stats.tirAboveUrgent, .red),
        ].filter { $0.1 > 0 }

        let total = segments.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    ForEach(segments.indices, id: \.self) { i in
                        let startAngle: Double = segments.prefix(i).reduce(0) { $0 + $1.1 } / total * 360
                        let endAngle: Double = startAngle + segments[i].1 / total * 360
                        Path { path in
                            path.move(to: center)
                            path.addArc(center: center, radius: radius,
                                        startAngle: .degrees(startAngle - 90),
                                        endAngle: .degrees(endAngle - 90),
                                        clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(segments[i].2)
                    }
                    Circle().fill(Color(.systemBackground)).frame(width: radius * 0.6, height: radius * 0.6)
                    Text("\(String(format: "%.0f", stats.tirInRange))%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            .frame(height: 220)
        )
    }

    private func color(for c: GlucoseClassification) -> Color {
        switch c {
        case .urgentLow, .urgentHigh: return .red
        case .low, .high: return .yellow
        case .inRange: return .green
        }
    }

    private func tirPill(_ label: String, _ pct: Double, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label): \(String(format: "%.0f", pct))%")
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

/// AGP percentile chart rendered as explicit closed polygons (port of xdrip's
/// `PercentileView.drawPolygon`). Each band is ONE closed `Path` — walk the upper
/// edge left→right, then the lower edge right→left, then close — so the fill can
/// never show internal gaps the way two overlapping SwiftUI `AreaMark` bands do.
/// The band wraps cyclically (hour 23 → hour 0, "00:00 == 24:00") like xdrip.
private struct AGPChartView: View {
    let data: [HourlyPercentiles]          // 24 entries, values already in display units
    let yDomain: ClosedRange<Double>
    let highLine: Double                   // display units
    let lowLine: Double                    // display units
    let yTicks: [(value: Double, label: String)]
    let outer: Color
    let inner: Color

    var body: some View {
        Canvas { ctx, size in
            guard data.count == 24 else { return }

            let leftInset: CGFloat = 30
            let bottomInset: CGFloat = 20
            let topInset: CGFloat = 6
            let plotLeft = leftInset
            let plotRight = size.width
            let plotTop = topInset
            let plotBottom = size.height - bottomInset
            let plotW = plotRight - plotLeft
            let plotH = plotBottom - plotTop
            let yLo = yDomain.lowerBound
            let yHi = yDomain.upperBound

            func x(_ hour: Double) -> CGFloat { plotLeft + plotW * CGFloat(hour / 24.0) }
            func y(_ v: Double) -> CGFloat {
                let t = (v - yLo) / (yHi - yLo)
                return plotBottom - plotH * CGFloat(t)
            }

            // Vertical gridlines every 3h (dashed).
            for h in stride(from: 0, through: 24, by: 3) {
                var g = Path()
                g.move(to: CGPoint(x: x(Double(h)), y: plotTop))
                g.addLine(to: CGPoint(x: x(Double(h)), y: plotBottom))
                ctx.stroke(g, with: .color(.white.opacity(0.10)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            // Horizontal gridlines + y labels.
            for tick in yTicks where tick.value >= yLo && tick.value <= yHi {
                var g = Path()
                g.move(to: CGPoint(x: plotLeft, y: y(tick.value)))
                g.addLine(to: CGPoint(x: plotRight, y: y(tick.value)))
                ctx.stroke(g, with: .color(.white.opacity(0.08)), lineWidth: 1)
                ctx.draw(Text(tick.label).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: leftInset / 2, y: y(tick.value)))
            }

            // One closed polygon per band (upper edge L→R, wrap, lower edge R→L).
            func band(_ lower: (HourlyPercentiles) -> Double,
                      _ upper: (HourlyPercentiles) -> Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: x(0), y: y(upper(data[0]))))
                for h in 1..<24 { p.addLine(to: CGPoint(x: x(Double(h)), y: y(upper(data[h])))) }
                p.addLine(to: CGPoint(x: x(24), y: y(upper(data[0]))))   // wrap top edge
                p.addLine(to: CGPoint(x: x(24), y: y(lower(data[0]))))   // drop to lower edge
                for h in stride(from: 23, through: 0, by: -1) {
                    p.addLine(to: CGPoint(x: x(Double(h)), y: y(lower(data[h]))))
                }
                p.closeSubpath()
                return p
            }
            ctx.fill(band({ $0.p10 }, { $0.p90 }), with: .color(outer))
            ctx.fill(band({ $0.p25 }, { $0.p75 }), with: .color(inner))

            // Median line (with cyclic wrap).
            var med = Path()
            med.move(to: CGPoint(x: x(0), y: y(data[0].p50)))
            for h in 1..<24 { med.addLine(to: CGPoint(x: x(Double(h)), y: y(data[h].p50))) }
            med.addLine(to: CGPoint(x: x(24), y: y(data[0].p50)))
            ctx.stroke(med, with: .color(.white), lineWidth: 2)

            // Threshold lines.
            var hi = Path()
            hi.move(to: CGPoint(x: plotLeft, y: y(highLine)))
            hi.addLine(to: CGPoint(x: plotRight, y: y(highLine)))
            ctx.stroke(hi, with: .color(.yellow.opacity(0.85)), lineWidth: 1.5)
            var lo = Path()
            lo.move(to: CGPoint(x: plotLeft, y: y(lowLine)))
            lo.addLine(to: CGPoint(x: plotRight, y: y(lowLine)))
            ctx.stroke(lo, with: .color(.red.opacity(0.85)), lineWidth: 1.5)

            // X-axis hour labels every 3h.
            for h in stride(from: 0, through: 24, by: 3) {
                let label = h == 24 ? "0" : "\(h)"
                ctx.draw(Text(label).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: x(Double(h)), y: plotBottom + 10))
            }
        }
    }
}
