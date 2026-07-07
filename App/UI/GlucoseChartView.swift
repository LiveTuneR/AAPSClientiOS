import SwiftUI
import Charts

struct GlucoseChartView: View {
    @ObservedObject var store: AppStore
    @Binding var selectedHours: Int
    @Binding var showIOB: Bool
    @Binding var showCOB: Bool
    @Binding var tappedTreatment: Treatment?

    private var units: GlucoseUnits { store.displayUnits }
    private var cutoff: Date { Date().addingTimeInterval(-Double(selectedHours) * 3600) }

    private var readingsInWindow: [GlucoseReading] {
        store.readings.filter { $0.date > cutoff }
    }

    private var carbsInWindow: [Treatment] {
        store.treatments.filter {
            ["Carb Correction", "Meal Bolus"].contains($0.eventType) && $0.date > cutoff && ($0.carbs ?? 0) > 0
        }
    }

    private var bolusesInWindow: [Treatment] {
        store.treatments.filter {
            ["Meal Bolus", "Correction Bolus", "Snack Bolus"].contains($0.eventType) && $0.date > cutoff && ($0.insulin ?? 0) > 0
        }
    }

    private var ttInWindow: [Treatment] {
        store.treatments.filter {
            $0.eventType == "Temporary Target" && $0.date > cutoff && ($0.durationMin ?? 0) > 0
        }
    }

    private var tempBasalTreatmentsInWindow: [Treatment] {
        store.treatments.filter { $0.eventType == "Temp Basal" && $0.date > cutoff.addingTimeInterval(-3600) }
    }

    private var basalSegmentsInWindow: [AAPSClientiOS.BasalSegment] {
        guard let basal = store.profile?.basal else { return [] }
        return AAPSClientiOS.basalSegments(basal: basal, windowStart: cutoff, windowEnd: chartXEnd)
    }

    private var actualBasalSegmentsInWindow: [ActualBasalSegment] {
        actualBasalSegments(
            scheduled: basalSegmentsInWindow,
            tempBasal: tempBasalTreatmentsInWindow,
            windowStart: cutoff,
            windowEnd: chartXEnd
        )
    }

    private struct PredictionLine { let color: Color; let points: [(Date, Int)] }

    private var predictionLines: [PredictionLine] {
        guard let pred = store.loopStatus?.predictions else { return [] }
        let now = Date()
        var lines: [PredictionLine] = []
        func pts(_ v: [Int]) -> [(Date, Int)] { v.prefix(13).enumerated().map { (now.addingTimeInterval(Double($0) * 300), $1) } }
        if !pred.iob.isEmpty { lines.append(PredictionLine(color: .purple, points: pts(pred.iob))) }
        if !pred.cob.isEmpty { lines.append(PredictionLine(color: .orange, points: pts(pred.cob))) }
        if !pred.zt.isEmpty  { lines.append(PredictionLine(color: .cyan, points: pts(pred.zt))) }
        if !pred.uam.isEmpty { lines.append(PredictionLine(color: .yellow, points: pts(pred.uam))) }
        return lines
    }

    private var statusInWindow: [DeviceStatusEntry] {
        store.deviceStatusHistory
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Chart layout helpers

    private func yVal(_ mgdl: Double) -> Double {
        units == .mmol ? mgdl / glucoseMmolFactor : mgdl
    }

    private var yDomain: ClosedRange<Double> {
        units == .mmol ? (30 / glucoseMmolFactor)...(300 / glucoseMmolFactor) : 30...300
    }

    private var chartXEnd: Date {
        predictionLines.flatMap { $0.points }.map { $0.0 }.max() ?? Date()
    }

    private var basalIcicleBandHeight: Double {
        (yDomain.upperBound - yDomain.lowerBound) * 0.16
    }

    private var basalMaxRateInWindow: Double {
        max((basalSegmentsInWindow.map(\.rate) + actualBasalSegmentsInWindow.map(\.rate)).max() ?? 0.5, 0.5)
    }

    private func basalIcicleY(_ rate: Double) -> Double {
        yDomain.upperBound - basalIcicleBandHeight * min(rate / basalMaxRateInWindow, 1.0)
    }

    // MARK: - Target timeline

    private func baseTargetMgdl() -> Double {
        if let p = store.profile, let lo = p.targetLow.first?.value, let hi = p.targetHigh.first?.value {
            var b = (lo + hi) / 2
            if b < 40 { b *= glucoseMmolFactor }
            return b
        }
        return 108
    }

    private func targetTimeline() -> [(Date, Double)] {
        let base = baseTargetMgdl()
        var pts: [(Date, Double)] = [(cutoff, base)]
        let tts = ttInWindow.compactMap { t -> (Date, Date, Double)? in
            guard let dur = t.durationMin, let any = t.targetBottom ?? t.targetTop else { return nil }
            var mid = (Double(t.targetBottom ?? any) + Double(t.targetTop ?? any)) / 2
            if mid < 40 { mid *= glucoseMmolFactor }
            let s = max(t.date, cutoff)
            let e = min(t.date.addingTimeInterval(Double(dur) * 60), chartXEnd)
            return e > s ? (s, e, mid) : nil
        }.sorted { $0.0 < $1.0 }
        for (s, e, v) in tts {
            pts.append((s, base)); pts.append((s, v))
            pts.append((e, v)); pts.append((e, base))
        }
        pts.append((chartXEnd, base))
        return pts
    }

    private func bgMgdl(at date: Date) -> Double {
        guard let nearest = store.readings.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        else { return 100 }
        return Double(nearest.mgdl)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Picker("Hours", selection: $selectedHours) {
                Text("3h").tag(3); Text("6h").tag(6); Text("12h").tag(12)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 6) {
                Spacer()
                subChartToggle("IOB", active: showIOB, color: .blue) { showIOB.toggle() }
                subChartToggle("COB", active: showCOB, color: .orange) { showCOB.toggle() }
            }
            Chart { chartContent }
                .chartYScale(domain: yDomain)
                .chartXScale(domain: cutoff...chartXEnd)
                .chartOverlay { proxy in
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { loc in
                            guard let d: Date = proxy.value(atX: loc.x, as: Date.self) else { return }
                            let all = carbsInWindow + bolusesInWindow + ttInWindow
                            if let n = all.min(by: { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }),
                               abs(n.date.timeIntervalSince(d)) < 300 {
                                tappedTreatment = n
                            }
                        }
                }
                .popover(item: $tappedTreatment) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.eventType).font(.headline)
                        Text(t.date.formatted(date: .abbreviated, time: .shortened))
                        if let i = t.insulin { Text(String(format: "%.2f U", i)) }
                        if let c = t.carbs  { Text(String(format: "%.0f g", c)) }
                        if let d = t.durationMin {
                            Text("\(d) min")
                            if let b = t.targetBottom, let tp = t.targetTop {
                                Text("\(b)–\(tp) \(units == .mmol ? "mmol/l" : "mg/dl")")
                            }
                        }
                    }
                    .padding()
                }
                .frame(height: 250)
            if showIOB && !statusInWindow.isEmpty { iobChart }
            if showCOB && !statusInWindow.isEmpty { cobChart }
        }
    }

    // MARK: - Chart content

    private static let basalColor = Color(red: 0.118, green: 0.588, blue: 0.988)

    @ChartContentBuilder private var chartContent: some ChartContent {
        ForEach(actualBasalSegmentsInWindow) { seg in
            RectangleMark(
                xStart: .value("T", seg.start), xEnd: .value("T", seg.end),
                yStart: .value("B", yDomain.upperBound), yEnd: .value("B", basalIcicleY(seg.rate))
            )
        }
        .foregroundStyle(Self.basalColor.opacity(0.4))
        ForEach(basalSegmentsInWindow) { seg in
            LineMark(x: .value("T", seg.start), y: .value("B", basalIcicleY(seg.rate)), series: .value("bs", "scheduled-basal"))
            LineMark(x: .value("T", seg.end), y: .value("B", basalIcicleY(seg.rate)), series: .value("bs", "scheduled-basal"))
        }
        .foregroundStyle(Self.basalColor.opacity(0.85))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        ForEach(readingsInWindow.reversed()) { r in
            LineMark(x: .value("T", r.date), y: .value("G", yVal(Double(r.mgdl))))
        }
        .foregroundStyle(Color.primary.opacity(0.4))
        ForEach(readingsInWindow.reversed()) { r in
            PointMark(x: .value("T", r.date), y: .value("G", yVal(Double(r.mgdl))))
                .foregroundStyle(Formatting.color(for: Formatting.classify(mgdl: r.mgdl, thresholds: store.thresholds)))
                .symbolSize(18)
        }
        ForEach(Array(targetTimeline().enumerated()), id: \.offset) { _, p in
            LineMark(x: .value("T", p.0), y: .value("Tgt", yVal(p.1)), series: .value("tgt", "target"))
        }
        .foregroundStyle(Color.teal.opacity(0.85))
        .lineStyle(StrokeStyle(lineWidth: 1.5))
        ForEach(carbsInWindow) { t in
            PointMark(x: .value("T", t.date), y: .value("D", yVal(bgMgdl(at: t.date))))
                .foregroundStyle(.orange).symbol(.circle)
                .symbolSize(min((t.carbs ?? 0) * 6 + 30, 220))
                .annotation(position: .top, spacing: 1) {
                    Text("\(Int(t.carbs ?? 0))").font(.system(size: 8)).foregroundColor(.orange)
                }
        }
        ForEach(bolusesInWindow) { t in
            PointMark(x: .value("T", t.date), y: .value("D", yVal(bgMgdl(at: t.date))))
                .foregroundStyle(.blue)
                .symbol { Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 6 + min((t.insulin ?? 0) * 2.5, 11)))
                    .foregroundStyle(.blue) }
                .annotation(position: .top, spacing: 2) {
                    Text(String(format: "%.1f", t.insulin ?? 0))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.blue)
                }
        }
        ForEach(predictionLines.indices, id: \.self) { i in
            let line = predictionLines[i]
            ForEach(line.points.indices, id: \.self) { j in
                LineMark(x: .value("T", line.points[j].0), y: .value("D", yVal(Double(line.points[j].1))), series: .value("pred", i))
            }
            .foregroundStyle(line.color).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        RectangleMark(
            xStart: .value("S", cutoff), xEnd: .value("E", chartXEnd),
            yStart: .value("L", yVal(Double(store.thresholds.low))), yEnd: .value("H", yVal(Double(store.thresholds.high)))
        ).foregroundStyle(Color.green.opacity(0.08))
        RuleMark(y: .value("L", yVal(Double(store.thresholds.low))))
            .foregroundStyle(.green.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
        RuleMark(y: .value("H", yVal(Double(store.thresholds.high))))
            .foregroundStyle(.green.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
    }

    // MARK: - IOB / COB sub-charts

    private var iobChart: some View {
        let values = statusInWindow.map { $0.iob }
        let absMax = max(values.map { abs($0) }.max() ?? 0, 0.5)
        let yRange = (-absMax * 1.2)...(absMax * 1.2)
        return Chart {
            ForEach(statusInWindow) { e in
                AreaMark(
                    x: .value("T", e.date),
                    yStart: .value("base", 0.0),
                    yEnd: .value("IOB", e.iob)
                )
                .foregroundStyle(Color.blue.opacity(0.7))
                .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Zero", 0.0))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartXScale(domain: cutoff...chartXEnd)
        .chartYScale(domain: yRange)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel { EmptyView() }
            }
        }
        .frame(height: 90)
        .overlay(alignment: .topLeading) {
            Text("IOB").font(.caption2).bold().foregroundColor(.blue)
                .padding(.leading, 6).padding(.top, 4)
        }
    }

    private var cobChart: some View {
        let maxCOB = max(statusInWindow.map { $0.cob }.max() ?? 0, 10.0)
        return Chart {
            ForEach(statusInWindow) { e in
                AreaMark(
                    x: .value("T", e.date),
                    yStart: .value("base", 0.0),
                    yEnd: .value("COB", e.cob)
                )
                .foregroundStyle(Color.orange.opacity(0.7))
                .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Zero", 0.0))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartXScale(domain: cutoff...chartXEnd)
        .chartYScale(domain: 0...(maxCOB * 1.2))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel { EmptyView() }
            }
        }
        .frame(height: 90)
        .overlay(alignment: .topLeading) {
            Text("COB").font(.caption2).bold().foregroundColor(.orange)
                .padding(.leading, 6).padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func subChartToggle(_ label: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? color : Color.primary.opacity(0.1))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

}
