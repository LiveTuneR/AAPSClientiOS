import Foundation

struct ActualBasalSegment: Equatable, Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let rate: Double
    let isTemp: Bool

    static func == (lhs: ActualBasalSegment, rhs: ActualBasalSegment) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.rate == rhs.rate && lhs.isTemp == rhs.isTemp
    }
}

/// Merges the scheduled-basal timeline with temp-basal treatments (eventType "Temp Basal")
/// to produce what the pump actually delivered, clipped to `[windowStart, windowEnd)`.
///
/// A later temp basal always cancels/overrides whatever was active before it (matches
/// AAPS/pump semantics — there is no separate "end" event). A `durationMin == 0` entry is a
/// pure cancel marker: it ends the previous override at its timestamp and contributes no
/// segment of its own. Percent-based temp basals resolve against the *scheduled* rate
/// covering their start time (not the rate of whatever override happened to be active).
func actualBasalSegments(
    scheduled: [BasalSegment],
    tempBasal: [Treatment],
    windowStart: Date,
    windowEnd: Date
) -> [ActualBasalSegment] {
    guard windowStart < windowEnd else { return [] }
    guard !tempBasal.isEmpty else {
        return scheduled.compactMap { seg in
            let s = max(seg.start, windowStart), e = min(seg.end, windowEnd)
            guard s < e else { return nil }
            return ActualBasalSegment(start: s, end: e, rate: seg.rate, isTemp: false)
        }
    }

    func scheduledRate(at date: Date) -> Double {
        scheduled.first { $0.start <= date && date < $0.end }?.rate ?? scheduled.last?.rate ?? 0
    }

    // Build override intervals, clipped by the next override's start (cancellation semantics).
    let sortedTemps = tempBasal
        .filter { ($0.durationMin ?? 0) >= 0 }
        .sorted { $0.date < $1.date }
    struct Override { let start: Date; var end: Date; let rate: Double }
    var overrides: [Override] = []
    for t in sortedTemps {
        let declaredEnd = t.date.addingTimeInterval(Double(t.durationMin ?? 0) * 60)
        if !overrides.isEmpty {
            overrides[overrides.count - 1].end = min(overrides[overrides.count - 1].end, t.date)
        }
        guard (t.durationMin ?? 0) > 0 else { continue }
        let rate = t.absolute ?? (t.tempBasalPercent.map { scheduledRate(at: t.date) * Double($0) / 100.0 } ?? scheduledRate(at: t.date))
        overrides.append(Override(start: t.date, end: declaredEnd, rate: rate))
    }

    // Cut points: scheduled-segment boundaries + override boundaries, clipped to window.
    var cuts: Set<TimeInterval> = [windowStart.timeIntervalSince1970, windowEnd.timeIntervalSince1970]
    for seg in scheduled { cuts.insert(seg.start.timeIntervalSince1970); cuts.insert(seg.end.timeIntervalSince1970) }
    for o in overrides { cuts.insert(o.start.timeIntervalSince1970); cuts.insert(o.end.timeIntervalSince1970) }
    let sortedCuts = cuts.sorted().map { Date(timeIntervalSince1970: $0) }.filter { $0 >= windowStart && $0 <= windowEnd }

    var result: [ActualBasalSegment] = []
    for i in 0..<max(sortedCuts.count - 1, 0) {
        let s = sortedCuts[i], e = sortedCuts[i + 1]
        guard s < e else { continue }
        let mid = s.addingTimeInterval(e.timeIntervalSince(s) / 2)
        if let active = overrides.first(where: { $0.start <= mid && mid < $0.end }) {
            result.append(ActualBasalSegment(start: s, end: e, rate: active.rate, isTemp: true))
        } else {
            result.append(ActualBasalSegment(start: s, end: e, rate: scheduledRate(at: mid), isTemp: false))
        }
    }
    return mergeAdjacent(result)
}

/// Coalesces consecutive segments with the same (rate, isTemp) to avoid seams in the chart.
private func mergeAdjacent(_ segs: [ActualBasalSegment]) -> [ActualBasalSegment] {
    var out: [ActualBasalSegment] = []
    for seg in segs {
        if let last = out.last, last.isTemp == seg.isTemp, abs(last.rate - seg.rate) < 0.0001, last.end == seg.start {
            out[out.count - 1] = ActualBasalSegment(start: last.start, end: seg.end, rate: last.rate, isTemp: last.isTemp)
        } else {
            out.append(seg)
        }
    }
    return out
}
