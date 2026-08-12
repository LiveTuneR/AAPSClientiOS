import SwiftUI

/// Shown when one or more alarms are currently firing (unsnoozed). Lets the
/// user silence them for a chosen duration instead of getting re-notified on
/// every refresh cycle while the underlying condition persists.
struct AlarmBannerView: View {
    @ObservedObject var store: AppStore
    @State private var snoozeMinutes: Double = 30

    var body: some View {
        if !store.activeAlarms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.red)
                    Text(titlesText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text(String(format: String(localized: "alarm.snooze_duration"), Int(snoozeMinutes)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44, alignment: .leading)
                    Slider(value: $snoozeMinutes, in: 15...120, step: 15)
                    Button(String(localized: "alarm.snooze_action")) {
                        store.snoozeAlarms(store.activeAlarms, minutes: Int(snoozeMinutes))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.12))
            .cornerRadius(12)
        }
    }

    private var titlesText: String {
        store.activeAlarms.map(\.title).joined(separator: " · ")
    }
}
