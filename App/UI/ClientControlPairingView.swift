import SwiftUI

struct ClientControlPairingView: View {
    @ObservedObject var store: AppStore

    @State private var pin = ""
    @State private var pairingStore = ClientPairingStore()
    @State private var matchedPayload: PairingPayload?
    @State private var isSearching = false
    @State private var statusText: String?
    @State private var isPaired = false

    var body: some View {
        Form {
            Section("Client Control") {
                if let pairing = pairingStore.currentPairing(), matchedPayload == nil {
                    LabeledContent("Client ID", value: pairing.clientId)
                    LabeledContent("Master", value: pairing.masterInstallId)
                    Button("Send Ping") { sendPing() }
                    Button("Unpair", role: .destructive) {
                        pairingStore.unpair()
                        isPaired = false
                        statusText = "Unpaired"
                    }
                } else {
                    TextField("8-digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: pin) { value in
                            pin = String(value.filter(\.isNumber).prefix(8))
                        }

                    Button(isSearching ? "Searching..." : "Find Pairing Offer") {
                        findOffer()
                    }
                    .disabled(pin.count != 8 || isSearching)
                }
            }

            if let payload = matchedPayload {
                Section("Confirm Master") {
                    LabeledContent("Master", value: payload.masterInstallId)
                    LabeledContent("Client ID", value: payload.clientId)
                    Button("Confirm Pairing") { confirm(payload) }
                }
            }

            if pairingStore.currentPairing() != nil, !store.clientControlAuthorized {
                Section {
                    Label(String(localized: "clientcontrol.orphaned_title"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(String(localized: "clientcontrol.orphaned_message"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let statusText {
                Section {
                    Text(statusText)
                        .foregroundColor(isPaired ? .green : .secondary)
                }
            }
        }
        .navigationTitle("Client Control")
    }

    private func findOffer() {
        isSearching = true
        statusText = nil
        matchedPayload = nil

        Task {
            do {
                store.ensureConfigured()
                let docs = try await store.client.searchSettings(limit: 500)
                let offers = docs.compactMap(offer(from:))
                let result = PairingOfferFetcher.match(offers: offers, pin: pin, now: Date())
                await MainActor.run {
                    switch result {
                    case .success(let payload):
                        matchedPayload = payload
                        statusText = "Pairing offer found"
                    case .ambiguous:
                        statusText = "More than one offer matched this PIN. Generate a new PIN and try again."
                    case .noMatch:
                        statusText = "No matching pairing offer found."
                    }
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    statusText = "Search failed: \(error)"
                    isSearching = false
                }
            }
        }
    }

    private func confirm(_ payload: PairingPayload) {
        let pairing = MasterPairing(
            masterInstallId: payload.masterInstallId,
            clientId: payload.clientId,
            secretHex: payload.secretHex
        )
        pairingStore.pair(pairing)
        isPaired = true
        matchedPayload = nil
        statusText = "Paired. Sending hello..."

        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                try await publisher.sendHello()
                await MainActor.run { statusText = "Paired and hello sent." }
            } catch {
                await MainActor.run { statusText = "Paired. Hello will need retry: \(error)" }
            }
        }
    }

    private func sendPing() {
        statusText = "Sending ping..."
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                let counter = try await publisher.sendPing()
                await MainActor.run { statusText = "Ping sent, waiting for ack..." }
                for _ in 0..<12 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let result = try await publisher.fetchAck(expectedCounter: counter)
                    if case .pending = result { continue }
                    await MainActor.run { statusText = describe(result) }
                    return
                }
                await MainActor.run { statusText = "Ping sent, no ack yet (master may be offline)." }
            } catch {
                await MainActor.run { statusText = "Ping failed: \(error)" }
            }
        }
    }

    private func describe(_ result: ClientControlPublisher.AckResult) -> String {
        switch result {
        case .pending: return "Ping sent, no ack yet."
        case .invalidSignature: return "Ack received but signature did not verify — rejected."
        case .staleTimestamp: return "Ack received but its timestamp is too far from device clock — rejected."
        case .terminal(.ok, _, _): return "Ping acknowledged by master."
        case .terminal(let status, let reason, _): return "Ping \(status.rawValue.lowercased())\(reason.map { ": \($0)" } ?? "")."
        }
    }

    private func offer(from document: NsSettingsDocument) -> PairingOffer? {
        guard document.identifier.hasPrefix(PairingOfferFetcher.offerIdentifierPrefix),
              let data = document.runningConfigJson.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(PairingOffer.self, from: data)
    }
}
