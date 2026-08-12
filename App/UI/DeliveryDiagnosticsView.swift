import SwiftUI

struct DeliveryDiagnosticsView: View {
    @State private var events: [DeliveryDiagnosticEvent] = []

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(
                    "diagnostics.empty",
                    systemImage: "waveform.path.ecg"
                )
            } else {
                ForEach(events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(event.channel).font(.caption).bold()
                            Spacer()
                            Text(event.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(event.state).font(.subheadline)
                        if let sequence = event.sequence {
                            Text("seq \(sequence)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let details = event.details {
                            Text(details).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("diagnostics.title")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: DeliveryDiagnostics.shared.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(events.isEmpty)
                Button(role: .destructive) {
                    DeliveryDiagnostics.shared.clear()
                    reload()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(events.isEmpty)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        events = DeliveryDiagnostics.shared.events()
    }
}
