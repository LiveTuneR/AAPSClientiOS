import SwiftUI

struct AddBlockSheetView: View {
    let schedule: String
    let displayUnits: GlucoseUnits
    let profileUnits: GlucoseUnits
    let existingSeconds: Set<Int>
    let onAdd: (Int, String) -> Void
    let onCancel: () -> Void

    @State private var time = Date()
    @State private var valueString = ""

    private var startSeconds: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60
    }

    private var isDuplicate: Bool {
        existingSeconds.contains(startSeconds)
    }

    private func toProfileValue(_ displayValue: Double) -> Double {
        switch schedule {
        case "basal", "carbratio": return displayValue
        default: return convertUnit(value: displayValue, from: displayUnits, to: profileUnits)
        }
    }

    private var isValid: Bool {
        guard !isDuplicate, let dv = Double(valueString) else { return false }
        return ProfileEdit.isValueInRange(toProfileValue(dv), schedule: schedule, profileUnits: profileUnits)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(String(localized: "edit.block_time"), selection: $time, displayedComponents: .hourAndMinute)
                TextField(String(localized: "edit.block_value"), text: $valueString)
                    .keyboardType(.decimalPad)
                if isDuplicate {
                    Text(String(localized: "edit.duplicate_time"))
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .navigationTitle(String(localized: "edit.add_block_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "edit.add_block")) {
                        onAdd(startSeconds, valueString)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
