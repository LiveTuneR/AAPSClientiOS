import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: AppStore

    private var units: GlucoseUnits { store.displayUnits }

    var body: some View {
        List(store.treatments.prefix(50), id: \.id) { treatment in
            HStack {
                VStack(alignment: .leading) {
                    Text(treatment.eventType)
                        .font(.headline)
                    Text(treatment.date, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let notes = treatment.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    if let insulin = treatment.insulin {
                        Text("\(String(format: "%.1f", insulin)) U")
                    }
                    if let carbs = treatment.carbs {
                        Text("\(String(format: "%.0f", carbs)) g")
                    }
                    if let absolute = treatment.absolute {
                        Text("\(String(format: "%.2f", absolute)) U/h")
                    } else if let pct = treatment.tempBasalPercent {
                        Text("\(pct)% basal")
                    }
                    if let lo = treatment.targetBottom {
                        Text(targetText(lo: lo, hi: treatment.targetTop ?? lo))
                    }
                    if let dur = treatment.durationMin {
                        Text("\(dur) min")
                    }
                }
                .font(.caption)
            }
        }
        .navigationTitle("history.title")
    }

    private func targetText(lo: Int, hi: Int) -> String {
        func conv(_ v: Int) -> String {
            units == .mmol ? String(format: "%.1f", Double(v) / glucoseMmolFactor) : "\(v)"
        }
        let suffix = units == .mmol ? "mmol/l" : "mg/dl"
        return lo == hi ? "\(conv(lo)) \(suffix)" : "\(conv(lo))–\(conv(hi)) \(suffix)"
    }
}
