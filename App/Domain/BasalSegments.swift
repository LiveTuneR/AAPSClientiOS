import Foundation

struct BasalSegment: Equatable, Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let rate: Double

    static func == (lhs: BasalSegment, rhs: BasalSegment) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.rate == rhs.rate
    }
}

func basalSegments(
    basal: [BasalEntry],
    windowStart: Date,
    windowEnd: Date,
    timeZone: TimeZone = .current
) -> [BasalSegment] {
    guard !basal.isEmpty, windowStart < windowEnd else { return [] }
    let sorted = basal.sorted { $0.startSeconds < $1.startSeconds }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    var segments: [BasalSegment] = []
    var day = calendar.startOfDay(for: windowStart)
    while day < windowEnd {
        for i in sorted.indices {
            let startSeconds = sorted[i].startSeconds
            let endSeconds = i + 1 < sorted.count ? sorted[i + 1].startSeconds : 86400
            guard let s = calendar.date(byAdding: .second, value: startSeconds, to: day),
                  let e = calendar.date(byAdding: .second, value: endSeconds, to: day) else { continue }
            guard s < windowEnd, e > windowStart else { continue }
            segments.append(BasalSegment(start: max(s, windowStart), end: min(e, windowEnd), rate: sorted[i].rate))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
    }
    return segments
}
