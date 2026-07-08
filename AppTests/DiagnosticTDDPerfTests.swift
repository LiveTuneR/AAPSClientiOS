import XCTest
@testable import AAPSClientiOS

/// Regression guard for a real perf bug: viewing 30-day TDD stats froze the UI for ~12s
/// (and 90-day for ~107s). Root cause was two-fold — `actualBasalSegments` did an O(cuts ×
/// overrides) linear scan instead of a binary search (fixed in ActualBasalSegments.swift),
/// and `StatisticsView.doses` was a computed property re-run 4x per render instead of cached
/// (fixed in StatisticsView.swift, see `recomputeDoses()`). This test only covers the domain
/// half — it can't see the view-layer 4x fix — but a regression in the O(n²) scan alone
/// would blow well past this budget.
final class DiagnosticTDDPerfTests: XCTestCase {

    private func syntheticTreatments(days: Int) -> [Treatment] {
        let now = Date()
        var out: [Treatment] = []
        var i = 0
        // Realistic dense closed-loop volume: a temp basal change every 5 minutes (AAPS-typical).
        var t = now
        let end = now.addingTimeInterval(-Double(days) * 86400)
        while t > end {
            i += 1
            out.append(Treatment(
                id: "tb\(i)", eventType: "Temp Basal", date: t,
                insulin: nil, carbs: nil, durationMin: 5, enteredBy: nil, notes: nil,
                targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
                absolute: Double.random(in: 0...2), tempBasalPercent: nil
            ))
            t = t.addingTimeInterval(-5 * 60)
        }
        for d in 0..<days {
            for b in 0..<3 {
                i += 1
                out.append(Treatment(
                    id: "b\(i)", eventType: "Meal Bolus", date: now.addingTimeInterval(-Double(d) * 86400 - Double(b) * 3600),
                    insulin: Double.random(in: 2...6), carbs: 30, durationMin: nil, enteredBy: nil, notes: nil,
                    targetBottom: nil, targetTop: nil, profileName: nil, percentage: nil,
                    absolute: nil, tempBasalPercent: nil
                ))
            }
        }
        return out
    }

    func test_dailyDoses30DaysStaysUnderBudgetWithDenseTempBasalHistory() {
        let treatments = syntheticTreatments(days: 30)
        let basal = [BasalEntry(startSeconds: 0, rate: 0.5), BasalEntry(startSeconds: 21600, rate: 0.7), BasalEntry(startSeconds: 43200, rate: 0.6)]
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now)!

        let t0 = Date()
        let doses = StatisticsCompute.dailyDoses(treatments: treatments, basal: basal, windowStart: start, windowEnd: now)
        let elapsed = Date().timeIntervalSince(t0)

        // 30 or 31 depending on calendar-day alignment of `windowStart` vs `now` — not the point
        // of this test (see budget assertion below), just a sanity check that it computed something.
        XCTAssertTrue((30...31).contains(doses.count), "expected ~30 days, got \(doses.count)")
        // Generous budget (measured ~0.5s post-fix; pre-fix this alone was ~3s, and the view
        // layer called it 4x on top of that) — catches a reintroduced O(n²) scan, not a tight timing assert.
        XCTAssertLessThan(elapsed, 3.0, "dailyDoses(30 days, \(treatments.count) treatments) took \(elapsed)s — investigate actualBasalSegments for a reintroduced O(cuts × overrides) scan")
    }
}
