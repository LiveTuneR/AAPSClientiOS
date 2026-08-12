import SwiftUI

struct BolusCalculatorView: View {
    @ObservedObject var store: AppStore

    @State private var pairingStore = ClientPairingStore()
    @State private var carbsText = ""
    @State private var bgText = ""
    @State private var useCob = true
    @State private var useIob = true
    @State private var useTt = true
    @State private var useTrend = true
    @State private var useBg = true
    @State private var percentage = 100
    @State private var isBusy = false
    @State private var statusText: String?
    @State private var preview: BolusPreview?

    private var isPaired: Bool { pairingStore.currentPairing() != nil }

    var body: some View {
        Form {
            Section {
                Text("Shows what the master's bolus wizard would currently calculate. This is informational only — nothing is sent to the pump, and no confirmation step exists in this app for it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !isPaired {
                Section {
                    Text("Pair with the master first (Settings → Client Control) to use the calculator.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section("Inputs") {
                    TextField("Carbs (g)", text: $carbsText).keyboardType(.numberPad)
                    TextField("BG override (mg/dl)", text: $bgText).keyboardType(.numberPad)
                    Toggle("Use COB", isOn: $useCob)
                    Toggle("Use IOB", isOn: $useIob)
                    Toggle("Use Temp Target", isOn: $useTt)
                    Toggle("Use Trend", isOn: $useTrend)
                    Toggle("Use BG", isOn: $useBg)
                    Stepper("Correction: \(percentage)%", value: $percentage, in: 0...200, step: 5)
                }

                Section {
                    Button(isBusy ? "Calculating..." : "Calculate") { calculate() }
                        .disabled(isBusy || carbsText.isEmpty)
                }

                if let detail = preview?.wizardDetail {
                    Section("Result") {
                        LabeledContent("Total", value: String(format: "%.2f U", detail.totalInsulin))
                        LabeledContent("From carbs", value: String(format: "%.2f U", detail.insulinFromCarbs))
                        LabeledContent("From BG", value: String(format: "%.2f U", detail.insulinFromBG))
                        LabeledContent("From COB", value: String(format: "%.2f U", detail.insulinFromCOB))
                        LabeledContent("From IOB", value: String(format: "%.2f U", detail.insulinFromBolusIOB + detail.insulinFromBasalIOB))
                        LabeledContent("IC", value: String(format: "%.1f", detail.ic))
                        LabeledContent("ISF", value: String(format: "%.1f", detail.sens))
                    }
                }

                if let preview {
                    Section("Master's Confirmation Text") {
                        ForEach(preview.lines, id: \.text) { Text($0.text) }
                    }
                }
            }

            if let statusText {
                Section { Text(statusText).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Bolus Calculator")
        .onAppear {
            if bgText.isEmpty, let last = store.readings.last {
                bgText = String(last.mgdl)
            }
        }
    }

    private func calculate() {
        guard let carbs = Int(carbsText) else { return }
        let bg = Double(bgText) ?? Double(store.readings.last?.mgdl ?? 0)
        isBusy = true
        statusText = "Calculating..."
        preview = nil
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            let inputs = ClientControlMessage.WizardPrepare(
                bg: bg, carbs: carbs, percentage: percentage, directCorrection: 0, carbTime: 0,
                useBg: useBg, useCob: useCob, useIob: useIob, useTt: useTt, useTrend: useTrend,
                alarm: false, notes: "", eCarbsGrams: 0, eCarbsDelayMinutes: 0, eCarbsDurationHours: 0,
                profileName: nil
            )
            do {
                let counter = try await publisher.sendWizardPrepare(inputs)
                let result = try await pollAck(publisher: publisher, counter: counter)
                await MainActor.run {
                    isBusy = false
                    switch result {
                    case .terminal(.ok, _, let payload):
                        guard let payload, let data = payload.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(BolusPreview.self, from: data) else {
                            statusText = "Response could not be read."
                            return
                        }
                        preview = decoded
                        statusText = nil
                    case .terminal(let status, let reason, _):
                        statusText = "Calculation \(status.rawValue.lowercased())\(reason.map { ": \($0)" } ?? "")."
                    case .pending:
                        statusText = "No response from master yet — try again."
                    case .invalidSignature:
                        statusText = "Ack signature did not verify — rejected."
                    case .staleTimestamp:
                        statusText = "Ack timestamp is too far from device clock — rejected."
                    }
                }
            } catch {
                await MainActor.run { isBusy = false; statusText = "Failed: \(error)" }
            }
        }
    }

    /// Matches the existing poll pattern in `ClientControlPairingView.sendPing()`.
    private func pollAck(publisher: ClientControlPublisher, counter: Int64) async throws -> ClientControlPublisher.AckResult {
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let result = try await publisher.fetchAck(expectedCounter: counter)
            if case .pending = result { continue }
            return result
        }
        return .pending
    }
}
