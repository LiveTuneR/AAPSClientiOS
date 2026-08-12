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
    @State private var progress: ProgressEnvelope?

    private var isPaired: Bool { pairingStore.currentPairing() != nil }

    var body: some View {
        Form {
            Section {
                Text("The master calculates and validates the dose. Delivery requires a separate confirmation below.")
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
                        Button("Confirm delivery") { commit(preview, asAdvisor: false) }
                            .buttonStyle(.borderedProminent)
                            .disabled(isBusy || (preview.wizardDetail?.totalInsulin ?? 0) <= 0)
                        if preview.advisorApplies {
                            Button("Confirm correction only") { commit(preview, asAdvisor: true) }
                                .disabled(isBusy)
                        }
                    }
                }

                if let progress {
                    Section("Delivery") {
                        ProgressView(value: Double(progress.percent), total: 100)
                        LabeledContent("Status", value: progress.status)
                        LabeledContent("Delivered", value: String(format: "%.2f U", progress.delivered))
                        if progress.phase == .active, progress.stopDeliveryEnabled {
                            Button("Stop delivery", role: .destructive) { stopDelivery() }
                                .disabled(isBusy)
                        }
                    }
                }
            }

            if let statusText {
                Section { Text(statusText).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Bolus Calculator")
        .onAppear {
            if bgText.isEmpty, let latest = store.readings.first {
                bgText = String(latest.mgdl)
            }
        }
    }

    private func calculate() {
        guard let carbs = Int(carbsText) else { return }
        let bg = Double(bgText) ?? Double(store.readings.first?.mgdl ?? 0)
        isBusy = true
        statusText = "Calculating..."
        preview = nil
        progress = nil
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

    private func commit(_ prepared: BolusPreview, asAdvisor: Bool) {
        isBusy = true
        statusText = "Sending confirmation..."
        let startedAt = Int64(Date().timeIntervalSince1970 * 1_000)
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                let counter = try await publisher.sendBolusCommit(
                    bolusId: prepared.bolusId,
                    asAdvisor: asAdvisor
                )
                let result = try await pollAck(publisher: publisher, counter: counter)
                switch result {
                case .terminal(.ok, _, _):
                    await MainActor.run {
                        statusText = "Accepted by master; waiting for pump delivery confirmation."
                    }
                    await monitorProgress(publisher: publisher, notBefore: startedAt - 5_000)
                case .terminal(let status, let reason, _):
                    await MainActor.run {
                        isBusy = false
                        statusText = "Delivery \(status.rawValue.lowercased())\(reason.map { ": \($0)" } ?? "")."
                    }
                case .pending:
                    await MainActor.run {
                        isBusy = false
                        statusText = "Delivery state is unconfirmed. Check the master before retrying."
                    }
                case .invalidSignature:
                    await MainActor.run {
                        isBusy = false
                        statusText = "Delivery acknowledgement signature is invalid."
                    }
                case .staleTimestamp:
                    await MainActor.run {
                        isBusy = false
                        statusText = "Delivery acknowledgement is stale."
                    }
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusText = "Delivery failed: \(error)"
                }
            }
        }
    }

    private func monitorProgress(publisher: ClientControlPublisher, notBefore: Int64) async {
        for _ in 0..<90 {
            if Task.isCancelled { return }
            if let frame = try? await publisher.fetchProgress(), frame.timestamp >= notBefore {
                await MainActor.run { progress = frame }
                switch frame.phase {
                case .complete:
                    await MainActor.run {
                        isBusy = false
                        preview = nil
                        statusText = "Pump delivery confirmed."
                    }
                    return
                case .cleared:
                    await MainActor.run {
                        isBusy = false
                        statusText = "Delivery ended before completion. Verify the pump and master."
                    }
                    return
                case .active:
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        await MainActor.run {
            isBusy = false
            statusText = "Master accepted the command, but final pump delivery was not confirmed."
        }
    }

    private func stopDelivery() {
        isBusy = true
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                try await publisher.sendStopBolus()
                await MainActor.run {
                    isBusy = false
                    statusText = "Stop request sent."
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusText = "Stop request failed: \(error)"
                }
            }
        }
    }

    /// Matches the existing poll pattern in `ClientControlPairingView.sendPing()`.
    private func pollAck(publisher: ClientControlPublisher, counter: Int64) async throws -> ClientControlPublisher.AckResult {
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let result = try await publisher.fetchAck(expectedCounter: counter)
            if case .pending = result { continue }
            return result
        }
        return .pending
    }
}
