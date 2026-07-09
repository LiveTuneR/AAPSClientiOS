import Foundation

final class ClientControlPublisher {
    enum PublishError: Error {
        case notPaired
        case signingFailed
    }

    private let client: NightscoutClient
    private let pairingStore: ClientPairingStore

    init(client: NightscoutClient, pairingStore: ClientPairingStore) {
        self.client = client
        self.pairingStore = pairingStore
    }

    @discardableResult
    func sendHello() async throws -> Int64 {
        try await send(
            type: ClientControlMessage.Hello.type,
            payload: ClientControlMessage.Hello(),
            identifierPrefix: "aaps_clientcontrol_hello_"
        )
    }

    @discardableResult
    func sendPing() async throws -> Int64 {
        try await send(
            type: ClientControlMessage.Ping.type,
            payload: ClientControlMessage.Ping(),
            identifierPrefix: "aaps_clientcontrol_cmd_ping_",
            wantsAck: true
        )
    }

    @discardableResult
    func sendScenePrepare(sceneId: String, durationMinutes: Int?) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.ScenePrepare.type,
            payload: ClientControlMessage.ScenePrepare(sceneId: sceneId, durationMinutes: durationMinutes),
            identifierPrefix: "aaps_clientcontrol_cmd_scene_prepare_",
            wantsAck: true
        )
    }

    @discardableResult
    func sendSceneCommit(bolusId: Int64) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.SceneCommit.type,
            payload: ClientControlMessage.SceneCommit(bolusId: bolusId),
            identifierPrefix: "aaps_clientcontrol_cmd_scene_commit_",
            wantsAck: true
        )
    }

    @discardableResult
    func sendSceneStop(triggerChain: Bool) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.SceneStop.type,
            payload: ClientControlMessage.SceneStop(triggerChain: triggerChain),
            identifierPrefix: "aaps_clientcontrol_cmd_scene_stop_",
            wantsAck: true
        )
    }

    /// Result of checking the master's `aaps_clientcontrol_ack_<clientId>` document against a
    /// specific command counter this client sent with `wantsAck: true`.
    enum AckResult: Equatable {
        /// Ack doc doesn't exist yet, or still reflects an older counter — command not yet acked.
        case pending
        /// Master processed the command; terminal outcome with optional reason AND the raw ack
        /// payload string (JSON-decode as `BolusPreview` when the command was a `..Prepare`; nil
        /// for commands with no payload, like `Ping`).
        case terminal(AckStatus, reason: String?, payload: String?)
        /// A doc for this counter exists but the HMAC signature doesn't verify against our shared
        /// secret — reject it rather than trust an unverifiable "Ok". Never silently treat as success.
        case invalidSignature
    }

    /// Fetches and verifies the ack for a command sent with counter `expectedCounter`. Mirrors the
    /// master's `writeAck` lifecycle (Executing/Pending -> Done/{Ok,Failed,Expired}) — a `.pending`
    /// result covers both "not written yet" and "still on the Executing phase".
    func fetchAck(expectedCounter: Int64) async throws -> AckResult {
        guard let pairing = pairingStore.currentPairing(),
              let secret = ClientControlCrypto.hexToBytes(pairing.secretHex) else {
            throw PublishError.notPaired
        }
        guard let document = try await client.fetchSettings(identifier: "aaps_clientcontrol_ack_\(pairing.clientId)"),
              let ackData = document.runningConfigJson.data(using: .utf8),
              let ack = try? JSONDecoder().decode(AckEnvelope.self, from: ackData) else {
            return .pending
        }
        guard ack.commandCounter == expectedCounter else {
            return .pending
        }
        guard ClientControlCrypto.verify(secret: secret, canonical: ack.canonicalString(), signature: ack.signature) else {
            return .invalidSignature
        }
        if ack.phase == .executing {
            return .pending
        }
        return .terminal(ack.status, reason: ack.reason, payload: ack.payload)
    }

    @discardableResult
    private func send<T: Encodable>(type: String, payload: T, identifierPrefix: String, wantsAck: Bool = false) async throws -> Int64 {
        guard let pairing = pairingStore.currentPairing(),
              let secret = ClientControlCrypto.hexToBytes(pairing.secretHex) else {
            throw PublishError.notPaired
        }

        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadJson = String(data: payloadData, encoding: .utf8) else {
            throw PublishError.signingFailed
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var envelope = SignedEnvelope(
            clientId: pairing.clientId,
            counter: pairingStore.nextCounter(),
            timestamp: nowMs,
            type: type,
            payload: payloadJson,
            signature: "",
            validUntil: nowMs + 5 * 60 * 1000,
            wantsAck: wantsAck
        )
        envelope.signature = ClientControlCrypto.sign(secret: secret, canonical: envelope.canonicalString())

        let envelopeData = try JSONEncoder().encode(envelope)
        guard let envelopeObject = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any] else {
            throw PublishError.signingFailed
        }

        let document: [String: Any] = [
            "date": nowMs,
            "utcOffset": 0,
            "app": "AAPS",
            "schemaVersion": 1,
            "envelope": envelopeObject,
        ]
        try await client.putSettings(identifier: "\(identifierPrefix)\(pairing.clientId)", document: document)
        return envelope.counter
    }
}
