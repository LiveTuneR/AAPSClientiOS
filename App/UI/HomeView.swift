import SwiftUI
import Charts

struct HomeView: View {
    @ObservedObject var store: AppStore
    let writer: NsTreatmentWriter

    @State private var showCarbs = false
    @State private var showTarget = false
    @State private var carbsGrams = ""
    @State private var targetMgdl = "100"
    @State private var targetDuration = "60"
    @State private var targetReason: TtReason = .eatingSoon
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var selectedHours = 3
    @State private var refreshError: String?
    @State private var tappedTreatment: Treatment?
    @State private var showProfileSwitch = false
    @State private var selectedProfileName = ""
    @State private var profilePercentage = "100"
    @State private var profileDuration = "0"
    @State private var showEventSheet = false
    @State private var showLoopMenu = false
    @State private var loopDuration = "60"
    @State private var showCarbsConfirm = false
    @State private var showIOB = false
    @State private var showCOB = false
    @State private var showBasal = false

    private var loopState: LoopState {
        LoopStateCalc.from(statusTimestamp: store.loopStatus?.timestamp, now: Date())
    }

    private var changeAges: [(icon: String, label: String, age: String)] {
        let now = Date()
        let events = store.careEvents
        let site = TreatmentAgeCalc.lastEventAge(treatments: events, eventTypes: ["Site Change"], now: now)
        let insulin = TreatmentAgeCalc.lastEventAge(treatments: events, eventTypes: ["Insulin Change"], now: now)
        let sensor = TreatmentAgeCalc.lastEventAge(treatments: events, eventTypes: ["Sensor Change", "Sensor Start"], now: now)
        let battery = TreatmentAgeCalc.lastEventAge(treatments: events, eventTypes: ["Pump Battery Change"], now: now)
        return [
            ("ivfluid.bag", "Cannula", TreatmentAgeCalc.formatAge(site)),
            ("syringe", "Insulin", TreatmentAgeCalc.formatAge(insulin)),
            ("waveform.path.ecg", "Sensor", TreatmentAgeCalc.formatAge(sensor)),
            ("battery.100percent", "Battery", TreatmentAgeCalc.formatAge(battery)),
        ]
    }

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

    private struct PredictionLine { let color: Color; let points: [(Date, Int)] }

    private var predictionLines: [PredictionLine] {
        guard let pred = store.loopStatus?.predictions else { return [] }
        let now = Date()
        var lines: [PredictionLine] = []
        func pts(_ v: [Int]) -> [(Date, Int)] { v.prefix(13).enumerated().map { (now.addingTimeInterval(Double($0) * 300), $1) } }
        if !pred.iob.isEmpty { lines.append(PredictionLine(color: .purple, points: pts(pred.iob))) }
        if !pred.cob.isEmpty { lines.append(PredictionLine(color: .orange, points: pts(pred.cob))) }
        if !pred.zt.isEmpty { lines.append(PredictionLine(color: .cyan, points: pts(pred.zt))) }
        if !pred.uam.isEmpty { lines.append(PredictionLine(color: .yellow, points: pts(pred.uam))) }
        return lines
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

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusCard
                if let err = refreshError {
                    Text(err).font(.caption2).foregroundColor(.red).padding(6).background(Color.red.opacity(0.1)).cornerRadius(6)
                }
                chartView
                actionBar
                if let msg = statusMessage {
                    Text(msg).foregroundColor(statusIsError ? .red : .green).font(.caption)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color(.systemBackground))
        .navigationTitle("app.title")
        .refreshable {
            do { try await store.refresh(); refreshError = nil }
            catch { refreshError = error.localizedDescription }
        }
        .task {
            // Only refetch if cached data is stale (switching tabs back won't reload).
            guard store.isStale else { return }
            do { try await store.refresh(); refreshError = nil }
            catch { refreshError = error.localizedDescription }
        }
        .sheet(isPresented: $showCarbs) { carbsSheet }
        .sheet(isPresented: $showTarget) { targetSheet }
        .sheet(isPresented: $showProfileSwitch) { profileSwitchSheet }
        .sheet(isPresented: $showEventSheet) { eventSheet }
        .confirmationDialog("Loop Mode", isPresented: $showLoopMenu) {
            Button("Close Loop") { setLoop("CLOSED_LOOP", 1440) }
            Button("Open Loop") { setLoop("OPEN_LOOP", 120) }
            Button("Suspend 30m") { setLoop("SUSPENDED_BY_USER", 30) }
            Button("Suspend 1h") { setLoop("SUSPENDED_BY_USER", 60) }
            Button("Suspend 2h") { setLoop("SUSPENDED_BY_USER", 120) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Requires NS Accept Running Mode on master device")
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 10) {
            mainGlucoseRow
            basalEventualRow
            statusRow
            changeAgesRow
            reasonChips
            profileChip
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }

    private var mainGlucoseRow: some View {
        HStack(alignment: .top) {
            ZStack {
                Circle()
                    .stroke(loopStateColor.opacity(0.3), lineWidth: 6)
                    .frame(width: 100, height: 100)
                if let latest = store.readings.first {
                    let classif = Formatting.classify(mgdl: latest.mgdl, thresholds: store.thresholds)
                    let delta = store.readings.dropFirst().first.map { latest.mgdl - $0.mgdl }
                    VStack(spacing: 0) {
                        Text(Formatting.format(latest.mgdl, units: units))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(color(for: classif))
                        HStack(spacing: 2) {
                            Text(Formatting.trendSymbol(latest.trend))
                                .font(.system(size: 16))
                            if let d = delta, d != 0 {
                                Text(deltaString(d))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(d > 0 ? .orange : .cyan)
                            }
                        }
                        let secs = Int(Date().timeIntervalSince(latest.date))
                        Text("\(secs / 60)m").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                } else {
                    Text("home.no_data").font(.system(size: 20, weight: .bold)).foregroundColor(.gray)
                }
            }
            .contentShape(Circle())
            .onTapGesture { showLoopMenu = true }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let latest = store.readings.first {
                    Text(latest.date.formatted(date: .omitted, time: .shortened)).font(.headline)
                }
                Text(loopPillText).font(.caption).foregroundColor(loopStateColor)
            }
        }
    }

    private var loopPillText: String {
        if let t = store.loopStatus?.timestamp {
            let min = Int(Date().timeIntervalSince(t) / 60)
            return "Loop \(min)m ago"
        }
        return "Loop —"
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            if let status = store.loopStatus {
                statusItem(icon: "syringe", label: "IOB", value: "\(String(format: "%.1f", status.iob))U")
                statusItem(icon: "takeoutbag.and.cup.and.straw", label: "COB", value: "\(String(format: "%.0f", status.cob))g")
                if let rate = status.tempBasalRate {
                    statusItem(icon: "infinity", label: "Basal", value: "\(String(format: "%.2f", rate))U/h")
                }
            }
            Spacer()
            if let status = store.loopStatus {
                if let res = status.pumpReservoir {
                    Text("\(String(format: "%.0f", res))U").font(.caption2).foregroundColor(.secondary)
                }
                if let bat = status.pumpBattery {
                    Text("\(bat)%").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private func statusItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundColor(.secondary)
            Text("\(label) \(value)").font(.caption2)
        }
    }

    private var basalEventualRow: some View {
        HStack {
            if let status = store.loopStatus {
                if let rate = status.tempBasalRate {
                    HStack(spacing: 4) {
                        Image(systemName: "infinity").font(.caption2)
                        Text("Basal \(String(format: "%.2f", rate))U/h").font(.caption2)
                    }
                }
                if let bg = status.eventualBgMgdl {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right").font(.caption2)
                        Text("eventBG \(gv(Double(bg)))").font(.caption2)
                    }
                }
            }
            Spacer()
        }
    }

    private var reasonChips: some View {
        Group {
            if let r = store.loopStatus?.reason, !r.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if let ts = store.loopStatus?.timestamp {
                        Text("Accepted \(ts.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        if let isf = r.isfMgdl { reasonChip("ISF", gv(isf)) }
                        if let cr = r.cr { reasonChip("CR", String(format: "%.0f", cr)) }
                        if let tg = r.targetMgdl { reasonChip("Target", gv(Double(tg))) }
                        if let dev = r.deviation { reasonChip("Dev", gv(dev)) }
                        if let bgi = r.bgi { reasonChip("BGI", gv(bgi)) }
                        if let minBg = r.minPredBg { reasonChip("minBG", gv(Double(minBg))) }
                    }
                }
            }
        }
    }

    private func reasonChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color(.systemGray5))
        .cornerRadius(4)
    }

    private var changeAgesRow: some View {
        HStack(spacing: 8) {
            ForEach(changeAges, id: \.label) { item in
                HStack(spacing: 2) {
                    Image(systemName: item.icon).font(.caption2).foregroundColor(.secondary)
                    Text(item.age).font(.caption2)
                }
            }
            Spacer()
            Button { showEventSheet = true } label: {
                Image(systemName: "plus.circle").font(.caption)
            }
        }
    }

    private var loopStateColor: Color {
        switch loopState {
        case .looping: return .green
        case .warning: return .yellow
        case .stale: return .red
        case .unknown: return .gray
        }
    }

    private var profileChip: some View {
        Group {
            if let name = store.activeProfileName {
                let pct = store.activeProfileSwitch?.percentage ?? 100
                HStack {
                    Image(systemName: "person.crop.circle").font(.caption)
                    Text(name).font(.caption).lineLimit(1)
                    if pct != 100 {
                        Text("(\(pct)%)").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color(.systemGray5))
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedProfileName = name
                    profilePercentage = String(pct)
                    profileDuration = "0"
                    showProfileSwitch = true
                }
            }
        }
    }

    // MARK: - Chart

    private func yVal(_ mgdl: Double) -> Double { units == .mmol ? mgdl / 18.0182 : mgdl }
    // Lower bound at 30 to give bolus spikes room below urgentLow (55).
    private var yDomain: ClosedRange<Double> { units == .mmol ? (30/18.0182)...(300/18.0182) : 30...300 }
    private var chartXEnd: Date { predictionLines.flatMap { $0.points }.map { $0.0 }.max() ?? Date() }

    private var statusInWindow: [DeviceStatusEntry] {
        store.deviceStatusHistory
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }
    /// Format a glucose-unit value (mg/dl) for display in selected units.
    private func gv(_ mgdl: Double) -> String { units == .mmol ? String(format: "%.1f", mgdl / 18.0182) : String(format: "%.0f", mgdl) }

    private func deltaString(_ d: Int) -> String {
        if units == .mmol {
            let v = Double(d) / 18.0182
            return v >= 0 ? String(format: "+%.1f", v) : String(format: "%.1f", v)
        }
        return d >= 0 ? "+\(d)" : "\(d)"
    }

    /// Base loop target (mg/dl) when no temp target is active.
    private func baseTargetMgdl() -> Double {
        if let p = store.profile, let lo = p.targetLow.first?.value, let hi = p.targetHigh.first?.value {
            var b = (lo + hi) / 2
            if b < 40 { b *= 18.0182 }   // profile may be in mmol → normalize
            return b
        }
        return 108
    }

    /// Continuous effective-target timeline (mg/dl): base target stepped up/down during each
    /// temp target — drawn as ONE unbroken line (AAPS-style), not floating segments.
    private func targetTimeline() -> [(Date, Double)] {
        let base = baseTargetMgdl()
        var pts: [(Date, Double)] = [(cutoff, base)]
        let tts = ttInWindow.compactMap { t -> (Date, Date, Double)? in
            guard let dur = t.durationMin, let any = t.targetBottom ?? t.targetTop else { return nil }
            var mid = (Double(t.targetBottom ?? any) + Double(t.targetTop ?? any)) / 2
            if mid < 40 { mid *= 18.0182 }
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

    private var chartView: some View {
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
                subChartToggle("Basal", active: showBasal, color: .teal) { showBasal.toggle() }
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
                               abs(n.date.timeIntervalSince(d)) < 300 { tappedTreatment = n }
                        }
                }
                .popover(item: $tappedTreatment) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.eventType).font(.headline)
                        Text(t.date.formatted(date: .abbreviated, time: .shortened))
                        if let i = t.insulin { Text(String(format: "%.2f U", i)) }
                        if let c = t.carbs { Text(String(format: "%.0f g", c)) }
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
            if showBasal && !basalSegmentsInWindow.isEmpty { basalChart }
        }
    }

    @ChartContentBuilder private var chartContent: some ChartContent {
        ForEach(readingsInWindow.reversed()) { r in
            LineMark(x: .value("T", r.date), y: .value("G", yVal(Double(r.mgdl))))
        }
        .foregroundStyle(Color.primary.opacity(0.4))
        ForEach(readingsInWindow.reversed()) { r in
            PointMark(x: .value("T", r.date), y: .value("G", yVal(Double(r.mgdl))))
                .foregroundStyle(color(for: Formatting.classify(mgdl: r.mgdl, thresholds: store.thresholds)))
                .symbolSize(18)
        }
        // Effective target — ONE continuous line: base target, stepped during temp targets.
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

    private var basalChart: some View {
        let scheduled = basalSegmentsInWindow
        let actual = actualBasalSegmentsInWindow
        let yMax = max((scheduled.map(\.rate) + actual.map(\.rate)).max() ?? 0.5, 0.5) * 1.2
        let tempStarts = tempBasalTreatmentsInWindow.filter { $0.date > cutoff && ($0.durationMin ?? 0) > 0 }
        return Chart {
            ForEach(scheduled) { seg in
                RectangleMark(
                    xStart: .value("T", seg.start), xEnd: .value("T", seg.end),
                    yStart: .value("B", 0.0), yEnd: .value("R", seg.rate)
                )
            }
            .foregroundStyle(Color.teal.opacity(0.18))
            ForEach(scheduled) { seg in
                LineMark(x: .value("T", seg.start), y: .value("R", seg.rate), series: .value("s", "scheduled"))
                LineMark(x: .value("T", seg.end), y: .value("R", seg.rate), series: .value("s", "scheduled"))
            }
            .foregroundStyle(Color.teal.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(actual) { seg in
                RectangleMark(
                    xStart: .value("T", seg.start), xEnd: .value("T", seg.end),
                    yStart: .value("B", 0.0), yEnd: .value("R", seg.rate)
                )
            }
            .foregroundStyle(Color.teal.opacity(0.55))

            ForEach(tempStarts, id: \.id) { t in
                PointMark(x: .value("T", t.date), y: .value("R", 0.0))
                    .symbol {
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 7))
                            .foregroundStyle((t.absolute ?? 1) <= 0.001 || t.tempBasalPercent == 0 ? Color.red.opacity(0.8) : Color.teal)
                    }
            }

            RuleMark(y: .value("Zero", 0.0))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartXScale(domain: cutoff...chartXEnd)
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel { EmptyView() }
            }
        }
        .frame(height: 90)
        .overlay(alignment: .topLeading) {
            Text("BASAL").font(.caption2).bold().foregroundColor(.teal)
                .padding(.leading, 6).padding(.top, 4)
        }
    }

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

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button { showCarbs = true } label: { Label("home.carbs", systemImage: "fork.knife").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button { showTarget = true } label: { Label("home.target", systemImage: "target").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private var carbsSheet: some View {
        NavigationStack {
            Form {
                TextField("action.grams", text: $carbsGrams).keyboardType(.decimalPad)
            }
            .navigationTitle("home.add_carbs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { showCarbs = false } }
                ToolbarItem(placement: .confirmationAction) { Button("send") { showCarbsConfirm = true }.disabled(carbsGrams.isEmpty) }
            }
        }
        .confirmationDialog("Confirm Carbs", isPresented: $showCarbsConfirm) {
            Button("Send \(carbsGrams)g", role: .destructive) { sendCarbs(); showCarbs = false }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Send \(carbsGrams)g carbs to Nightscout?")
        }
    }

    private var targetSheet: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    HStack(spacing: 8) {
                        ttPresetButton("Eating Soon", .eatingSoon, targetMgdl: 90, duration: 45)
                        ttPresetButton("Activity", .activity, targetMgdl: 140, duration: 90)
                        ttPresetButton("Hypo", .hypo, targetMgdl: 150, duration: 60)
                    }
                }
                HStack {
                    TextField("action.target", text: $targetMgdl).keyboardType(.decimalPad)
                    Text(units == .mmol ? "mmol/l" : "mg/dl").foregroundColor(.secondary)
                }
                TextField("action.duration_min", text: $targetDuration).keyboardType(.numberPad)
                Picker("action.reason", selection: $targetReason) {
                    Text("Eating Soon").tag(TtReason.eatingSoon)
                    Text("Activity").tag(TtReason.activity)
                    Text("Hypo").tag(TtReason.hypo)
                    Text("Custom").tag(TtReason.custom)
                }
                Button("action.cancel_target", role: .destructive) { cancelTarget(); showTarget = false }
            }
            .navigationTitle("home.temp_target")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { showTarget = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("set") { sendTarget(); showTarget = false }.disabled(targetMgdl.isEmpty || targetDuration.isEmpty)
                }
            }
        }
    }

    private func ttPresetButton(_ label: String, _ reason: TtReason, targetMgdl presetMgdl: Int, duration: Int) -> some View {
        Button(label) {
            let v = units == .mmol ? String(format: "%.1f", Double(presetMgdl) / 18.0182) : "\(presetMgdl)"
            targetMgdl = v
            targetDuration = "\(duration)"
            targetReason = reason
        }
        .buttonStyle(.bordered)
        .font(.caption)
        .controlSize(.small)
    }

    // MARK: - Actions logic

    private func sendCarbs() {
        guard let grams = Double(carbsGrams), grams > 0 else { return }
        Task {
            do {
                try await writer.sendCarbs(grams: grams, at: Date())
                statusMessage = String(localized: "home.carbs_sent"); statusIsError = false; carbsGrams = ""
                try? await store.refresh()
            } catch { statusMessage = error.localizedDescription; statusIsError = true }
        }
    }

    private func sendTarget() {
        let raw = targetMgdl.replacingOccurrences(of: ",", with: ".")
        guard let entered = Double(raw), let dur = Int(targetDuration), entered > 0, dur > 0 else { return }
        let mgdl = units == .mmol ? Int((entered * 18.0182).rounded()) : Int(entered)
        Task {
            do {
                try await writer.sendTempTarget(targetMgdl: mgdl, durationMin: dur, reason: targetReason)
                statusMessage = String(localized: "home.target_set"); statusIsError = false
                try? await store.refresh()
            } catch { statusMessage = error.localizedDescription; statusIsError = true }
        }
    }

    private func cancelTarget() {
        Task {
            do {
                try await writer.cancelTempTarget()
                statusMessage = String(localized: "home.target_cancelled"); statusIsError = false
                try? await store.refresh()
            } catch { statusMessage = error.localizedDescription; statusIsError = true }
        }
    }

    private func color(for classification: GlucoseClassification) -> Color {
        switch classification {
        case .urgentLow: return .red
        case .low: return .yellow
        case .inRange: return .green
        case .high: return .yellow
        case .urgentHigh: return .red
        }
    }

    // MARK: - Profile Switch

    private var profileSwitchSheet: some View {
        NavigationStack {
            Form {
                if let store = store.profileStore {
                    Picker("Profile", selection: $selectedProfileName) {
                        ForEach(store.profileNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                TextField("Percentage (30-250)", text: $profilePercentage).keyboardType(.numberPad)
                TextField("Duration (0=permanent)", text: $profileDuration).keyboardType(.numberPad)
            }
            .navigationTitle("Profile Switch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { showProfileSwitch = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Switch") {
                        switchProfile()
                        showProfileSwitch = false
                    }
                    .disabled(selectedProfileName.isEmpty)
                }
            }
        }
    }

    private func switchProfile() {
        guard let pct = Int(profilePercentage), (30...250).contains(pct),
              let dur = Int(profileDuration), dur >= 0 else { return }
        let json = store.profileStore?.rawJson[selectedProfileName]
        Task {
            do {
                try await writer.switchProfile(name: selectedProfileName, percentage: pct, durationMin: dur, profileJson: json)
                statusMessage = "Profile switched"
                statusIsError = false
                try? await store.refresh()
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    // MARK: - Care Portal Event

    @State private var eventType = "Site Change"
    @State private var eventNotes = ""
    @State private var eventGlucose = ""
    @State private var eventDuration = ""

    private var eventSheet: some View {
        NavigationStack {
            Form {
                Picker("Event", selection: $eventType) {
                    Text("Site Change").tag("Site Change")
                    Text("Insulin Change").tag("Insulin Change")
                    Text("Pump Battery Change").tag("Pump Battery Change")
                    Text("Sensor Change").tag("Sensor Change")
                    Text("Sensor Start").tag("Sensor Start")
                    Text("Note").tag("Note")
                    Text("BG Check").tag("BG Check")
                    Text("Exercise").tag("Exercise")
                }
                TextField("Notes", text: $eventNotes)
                if eventType == "BG Check" {
                    TextField("Glucose (mg/dl)", text: $eventGlucose).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Log Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { showEventSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("send") {
                        logEvent()
                        showEventSheet = false
                    }
                }
            }
        }
    }

    private func logEvent() {
        let glucose = Int(eventGlucose)
        Task {
            do {
                try await writer.logEvent(
                    eventType: eventType,
                    at: Date(),
                    notes: eventNotes.isEmpty ? nil : eventNotes,
                    glucoseMgdl: glucose,
                    durationMin: eventDuration.isEmpty ? nil : Int(eventDuration)
                )
                statusMessage = "Event logged"
                statusIsError = false
                try? await store.refresh()
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func setLoop(_ mode: String, _ durationMin: Int) {
        Task {
            do {
                try await writer.setLoopMode(mode, durationMin: durationMin)
                statusMessage = "Loop command sent"
                statusIsError = false
                try? await store.refresh()
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }
}
