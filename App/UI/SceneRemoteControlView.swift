import SwiftUI

struct SceneRemoteControlView: View {
    @ObservedObject var store: AppStore

    @State private var pairingStore = ClientPairingStore()
    @State private var preparedPreview: BolusPreview?
    @State private var preparedSceneId: String?
    @State private var statusText: String?
    @State private var isBusy = false

    private var isPaired: Bool { pairingStore.currentPairing() != nil }

    var body: some View {
        Form {
            if !isPaired {
                Section {
                    Text("Pair with the master first (Settings -> Client Control) to activate scenes remotely.")
                        .foregroundColor(.secondary)
                }
            } else {
                if let active = store.activeRemoteSceneDefinition {
                    Section("Active Scene") {
                        LabeledContent("Scene", value: store.activeRemoteSceneDisplayName ?? active.sceneId)
                        Button("Stop Scene", role: .destructive) { stopScene(triggerChain: false) }
                            .disabled(isBusy)
                    }
                }

                Section("Available Scenes") {
                    ForEach(store.remoteSceneDefinitions) { scene in
                        Button(scene.name ?? scene.sceneId) { prepare(scene.sceneId) }
                            .disabled(isBusy)
                    }
                }

                if let preview = preparedPreview, let sceneId = preparedSceneId {
                    Section("Confirm Activation") {
                        ForEach(preview.lines, id: \.text) { line in
                            Text(line.text)
                        }
                        Button("Confirm") { commit(preview.bolusId) }
                        Button("Cancel", role: .cancel) {
                            preparedPreview = nil
                            preparedSceneId = nil
                        }
                        .accessibilityIdentifier("cancel_scene_prepare_\(sceneId)")
                    }
                }
            }

            if let statusText {
                Section {
                    Text(statusText)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Scenes")
    }

    private func prepare(_ sceneId: String) {
        isBusy = true
        statusText = "Preparing..."
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                let counter = try await publisher.sendScenePrepare(sceneId: sceneId, durationMinutes: nil)
                let result = try await pollAck(publisher: publisher, counter: counter)
                await MainActor.run {
                    isBusy = false
                    switch result {
                    case .terminal(.ok, _, let payload):
                        guard let payload, let data = payload.data(using: .utf8),
                              let preview = try? JSONDecoder().decode(BolusPreview.self, from: data) else {
                            statusText = "Prepared, but preview could not be read."
                            return
                        }
                        preparedPreview = preview
                        preparedSceneId = sceneId
                        statusText = nil
                    case .terminal(let status, let reason, _):
                        statusText = "Prepare \(status.rawValue.lowercased())\(reason.map { ": \($0)" } ?? "")."
                    case .pending:
                        statusText = "No response from master yet - try again."
                    case .invalidSignature:
                        statusText = "Ack signature did not verify - rejected."
                    case .staleTimestamp:
                        statusText = "Ack timestamp is too far from device clock - rejected."
                    }
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusText = "Failed: \(error)"
                }
            }
        }
    }

    private func commit(_ bolusId: Int64) {
        isBusy = true
        statusText = "Activating..."
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                let counter = try await publisher.sendSceneCommit(bolusId: bolusId)
                let result = try await pollAck(publisher: publisher, counter: counter)
                await MainActor.run {
                    isBusy = false
                    switch result {
                    case .terminal(.ok, _, _):
                        preparedPreview = nil
                        preparedSceneId = nil
                        statusText = "Scene activation confirmed."
                        Task { try? await store.refresh() }
                    case .terminal(let status, let reason, _):
                        statusText = "Activation \(status.rawValue.lowercased())\(reason.map { ": \($0)" } ?? "")."
                    case .pending:
                        statusText = "Activation was sent but not confirmed. Check the master before retrying."
                    case .invalidSignature:
                        statusText = "Activation acknowledgement signature is invalid."
                    case .staleTimestamp:
                        statusText = "Activation acknowledgement is stale."
                    }
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusText = "Commit failed: \(error)"
                }
            }
        }
    }

    private func stopScene(triggerChain: Bool) {
        isBusy = true
        statusText = "Stopping..."
        Task {
            let publisher = ClientControlPublisher(client: store.client, pairingStore: pairingStore)
            do {
                try await publisher.sendSceneStop(triggerChain: triggerChain)
                try? await store.refresh()
                await MainActor.run {
                    isBusy = false
                    statusText = "Stop request sent."
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    statusText = "Stop failed: \(error)"
                }
            }
        }
    }

    /// Polls a few times with a short delay — the master's ack write isn't instant. Matches the
    /// existing pattern in `ClientControlPairingView.sendPing()`.
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
