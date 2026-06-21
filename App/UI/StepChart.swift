import SwiftUI
import Charts

struct StepChart: View {
    let points: [(hour: Double, value: Double)]
    let unitLabel: String
    let color: Color

    var body: some View {
        Chart {
            ForEach(0..<points.count - 1, id: \.self) { i in
                let p = points[i]
                let next = points[i + 1]
                if p.hour < next.hour {
                    RectangleMark(
                        xStart: .value("S", p.hour),
                        xEnd: .value("E", next.hour),
                        yStart: .value("B", 0),
                        yEnd: .value("V", p.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            ForEach(points, id: \.hour) { p in
                LineMark(x: .value("h", p.hour), y: .value("v", p.value))
            }
        }
        .foregroundStyle(color)
        .chartXScale(domain: 0.0...24.0)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7))
        }
        .chartYAxisLabel(unitLabel)
        .frame(height: 100)
    }
}

func stepChartPoints(_ blocks: [(startSeconds: Int, value: Double)]) -> [(hour: Double, value: Double)] {
    guard !blocks.isEmpty else { return [] }
    let sorted = blocks.sorted { $0.startSeconds < $1.startSeconds }
    var points: [(hour: Double, value: Double)] = []
    for i in 0..<sorted.count {
        let hour = Double(sorted[i].startSeconds) / 3600.0
        if i > 0 { points.append((hour, sorted[i - 1].value)) }
        points.append((hour, sorted[i].value))
    }
    points.append((24.0, sorted.last!.value))
    return points
}

func dailyBasalUnits(_ blocks: [(startSeconds: Int, rate: Double)]) -> Double {
    guard !blocks.isEmpty else { return 0 }
    let sorted = blocks.sorted { $0.startSeconds < $1.startSeconds }
    var total = 0.0
    for i in 0..<sorted.count {
        let nextStart = i + 1 < sorted.count ? sorted[i + 1].startSeconds : 86400
        let durationHours = Double(nextStart - sorted[i].startSeconds) / 3600.0
        total += sorted[i].rate * durationHours
    }
    return total
}
