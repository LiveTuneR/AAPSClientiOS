import SwiftUI

struct DeliveryDiagnosticsView: View {
    @State private var events: [DeliveryDiagnosticEvent] = []

    var body: some View {
        List {
            if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("diagnostics.empty")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
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
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                ShareLink(item: DeliveryDiagnostics.shared.exportText()) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(events.isEmpty)
                Button(role: .destructive) {
                    DeliveryDiagnostics.shared.clear()
                    reload()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(events.isEmpty)
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        events = DeliveryDiagnostics.shared.events()
    }
}
