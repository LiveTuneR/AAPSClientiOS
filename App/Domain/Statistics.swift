import Foundation

struct GlucoseStats: Equatable {
    let count: Int
    let averageMgdl: Double
    let gmiPercent: Double
    let cvPercent: Double
    let sdMgdl: Double
    let tirBelowUrgent: Double
    let tirBelow: Double
    let tirInRange: Double
    let tirAbove: Double
    let tirAboveUrgent: Double
}

enum StatisticsCompute {
    static func stats(readings: [GlucoseReading], thresholds: AlarmThresholds) -> GlucoseStats {
        let values = readings.map { Double($0.mgdl) }
        let count = values.count
        guard count > 1 else {
            return GlucoseStats(
                count: count, averageMgdl: values.first ?? 0, gmiPercent: 0, cvPercent: 0,
                sdMgdl: 0, tirBelowUrgent: 0, tirBelow: 0, tirInRange: 0, tirAbove: 0, tirAboveUrgent: 0
            )
        }
        let mean = values.reduce(0, +) / Double(count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count - 1)
        let sd = sqrt(variance)
        let cv = sd / mean * 100
        let gmi = 3.31 + 0.02392 * mean

        func pct(_ cond: (Int) -> Bool) -> Double {
            Double(readings.filter { cond($0.mgdl) }.count) / Double(count) * 100
        }

        return GlucoseStats(
            count: count,
            averageMgdl: mean,
            gmiPercent: gmi,
            cvPercent: cv,
            sdMgdl: sd,
            tirBelowUrgent: pct { $0 < thresholds.urgentLow },
            tirBelow: pct { $0 >= thresholds.urgentLow && $0 < thresholds.low },
            tirInRange: pct { $0 >= thresholds.low && $0 <= thresholds.high },
            tirAbove: pct { $0 > thresholds.high && $0 < thresholds.urgentHigh },
            tirAboveUrgent: pct { $0 >= thresholds.urgentHigh }
        )
    }
}

struct HourlyPercentiles: Identifiable, Equatable {
    let hour: Int
    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double
    var id: Int { hour }
}

extension StatisticsCompute {
    static func hourlyPercentiles(readings: [GlucoseReading], units: GlucoseUnits) -> [HourlyPercentiles] {
        let calendar = Calendar.current
        var byHour: [Int: [Double]] = [:]
        for r in readings {
            let h = calendar.component(.hour, from: r.date)
            let val = units == .mmol ? Double(r.mgdl) / glucoseMmolFactor : Double(r.mgdl)
            byHour[h, default: []].append(val)
        }
        // Compute percentiles for hours that have data.
        var raw: [Int: HourlyPercentiles] = [:]
        for h in 0..<24 {
            guard let vals = byHour[h], !vals.isEmpty else { continue }
            let sorted = vals.sorted()
            func p(_ pct: Double) -> Double {
                let idx = pct * Double(sorted.count - 1)
                let lo = Int(idx), hi = min(lo + 1, sorted.count - 1)
                return sorted[lo] + (idx - Double(lo)) * (sorted[hi] - sorted[lo])
            }
            raw[h] = HourlyPercentiles(hour: h, p10: p(0.10), p25: p(0.25), p50: p(0.50), p75: p(0.75), p90: p(0.90))
        }
        guard !raw.isEmpty else { return [] }
        // Fill all 24 hours by interpolating from nearest neighbours (circular).
        return (0..<24).map { h in
            if let hp = raw[h] { return hp }
            for dist in 1..<24 {
                let l = raw[(h - dist + 24) % 24]
                let r = raw[(h + dist) % 24]
                if let l, let r {
                    return HourlyPercentiles(hour: h,
                        p10: (l.p10 + r.p10) / 2, p25: (l.p25 + r.p25) / 2,
                        p50: (l.p50 + r.p50) / 2, p75: (l.p75 + r.p75) / 2,
                        p90: (l.p90 + r.p90) / 2)
                }
                // Single neighbour fallback
                if let n = l ?? r {
                    return HourlyPercentiles(hour: h, p10: n.p10, p25: n.p25,
                                             p50: n.p50, p75: n.p75, p90: n.p90)
                }
            }
            return HourlyPercentiles(hour: h, p10: 0, p25: 0, p50: 0, p75: 0, p90: 0)
        }
    }
}
