import Foundation

final class ClientControlPublisher {
    static let roundTripTTL: Int64 = 8_000
    static let pumpRoundTripTTL: Int64 = 60_000
    static let pingTTL: Int64 = 10_000
    static let fireAndForgetTTL: Int64 = 5 * 60 * 1_000
    static let documentDate: Int64 = 946_684_800_001

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
            wantsAck: true,
            ttlMs: Self.pingTTL
        )
    }

    @discardableResult
    func sendWizardPrepare(_ inputs: ClientControlMessage.WizardPrepare) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.WizardPrepare.type,
            payload: inputs,
            identifierPrefix: "aaps_clientcontrol_cmd_wizard_prepare_",
            wantsAck: true,
            ttlMs: Self.roundTripTTL
        )
    }

    @discardableResult
    func sendScenePrepare(sceneId: String, durationMinutes: Int?) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.ScenePrepare.type,
            payload: ClientControlMessage.ScenePrepare(sceneId: sceneId, durationMinutes: durationMinutes),
            identifierPrefix: "aaps_clientcontrol_cmd_scene_prepare_",
            wantsAck: true,
            ttlMs: Self.roundTripTTL
        )
    }

    @discardableResult
    func sendSceneCommit(bolusId: Int64) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.SceneCommit.type,
            payload: ClientControlMessage.SceneCommit(bolusId: bolusId),
            identifierPrefix: "aaps_clientcontrol_cmd_scene_commit_",
            wantsAck: true,
            ttlMs: Self.roundTripTTL
        )
    }

    @discardableResult
    func sendSceneStop(triggerChain: Bool) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.SceneStop.type,
            payload: ClientControlMessage.SceneStop(triggerChain: triggerChain),
            identifierPrefix: "aaps_clientcontrol_cmd_scene_stop_",
            wantsAck: false,
            ttlMs: Self.fireAndForgetTTL
        )
    }

    @discardableResult
    func sendPreferencesUpdate(_ prefs: [String: PrefEntry]) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.PreferencesUpdate.type,
            payload: ClientControlMessage.PreferencesUpdate(prefs: prefs),
            identifierPrefix: "aaps_clientcontrol_cmd_preferences_update_",
            wantsAck: true,
            ttlMs: Self.roundTripTTL
        )
    }

    @discardableResult
    func sendBolusPrepare(guid: String) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.BolusPrepare.type,
            payload: ClientControlMessage.BolusPrepare(guid: guid),
            identifierPrefix: "aaps_clientcontrol_cmd_bolus_prepare_",
            wantsAck: true,
            ttlMs: Self.roundTripTTL
        )
    }

    @discardableResult
    func sendBatchPrepare(_ actions: [BatchActionDto]) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.BatchPrepare.type,
            payload: ClientControlMessage.BatchPrepare(actions: actions),
            identifierPrefix: "aaps_clientcontrol_cmd_batch_prepare_",
            wantsAck: true,
            ttlMs: Self.roundTripTTL
        )
    }

    @discardableResult
    func sendBolusCommit(
        bolusId: Int64,
        asAdvisor: Bool = false,
        correctionU: Double = 0,
        pumpDirect: Bool = false
    ) async throws -> Int64 {
        try await send(
            type: ClientControlMessage.BolusCommit.type,
            payload: ClientControlMessage.BolusCommit(
                bolusId: bolusId, asAdvisor: asAdvisor, correctionU: correctionU
            ),
            identifierPrefix: "aaps_clientcontrol_cmd_bolus_commit_",
            wantsAck: true,
            ttlMs: pumpDirect ? Self.pumpRoundTripTTL : Self.roundTripTTL
        )
    }

    @discardableResult
    func sendDismissAlarm() async throws -> Int64 {
        try await send(
            type: ClientControlMessage.DismissAlarm.type,
            payload: ClientControlMessage.DismissAlarm(),
            identifierPrefix: "aaps_clientcontrol_cmd_dismiss_alarm_",
            ttlMs: Self.fireAndForgetTTL
        )
    }

    @discardableResult
    func sendStopBolus() async throws -> Int64 {
        try await send(
            type: ClientControlMessage.StopBolus.type,
            payload: ClientControlMessage.StopBolus(),
            identifierPrefix: "aaps_clientcontrol_cmd_stop_bolus_",
            ttlMs: Self.fireAndForgetTTL
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
        /// Signature verifies, but `ack.timestamp` falls outside the allowed clock-skew window —
        /// e.g. a stale ack doc served from a cache, or a master with a badly wrong clock. Reject
        /// rather than trust a terminal outcome we can't date.
        case staleTimestamp
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
        let ackDate = Date(timeIntervalSince1970: Double(ack.timestamp) / 1000)
        guard ClientControlCrypto.timestampWithinSkew(ackDate, now: Date()) else {
            return .staleTimestamp
        }
        if ack.phase == .executing {
            return .pending
        }
        return .terminal(ack.status, reason: ack.reason, payload: ack.payload)
    }

    func fetchProgress() async throws -> ProgressEnvelope? {
        guard let pairing = pairingStore.currentPairing(),
              let secret = ClientControlCrypto.hexToBytes(pairing.secretHex) else {
            throw PublishError.notPaired
        }
        guard let document = try await client.fetchSettings(
            identifier: "aaps_clientcontrol_progress_\(pairing.clientId)"
        ), let data = document.runningConfigJson.data(using: .utf8),
           let progress = try? JSONDecoder().decode(ProgressEnvelope.self, from: data),
           progress.clientId == pairing.clientId else { return nil }
        guard ClientControlCrypto.verify(
            secret: secret, canonical: progress.canonicalString(), signature: progress.signature
        ) else { return nil }
        let date = Date(timeIntervalSince1970: Double(progress.timestamp) / 1_000)
        guard ClientControlCrypto.timestampWithinSkew(date, now: Date()) else { return nil }
        return progress
    }

    @discardableResult
    private func send<T: Encodable>(
        type: String,
        payload: T,
        identifierPrefix: String,
        wantsAck: Bool = false,
        ttlMs: Int64 = ClientControlPublisher.fireAndForgetTTL
    ) async throws -> Int64 {
        guard let pairing = pairingStore.currentPairing(),
              let secret = ClientControlCrypto.hexToBytes(pairing.secretHex) else {
            throw PublishError.notPaired
        }

        let encodedPayload = try JSONEncoder().encode(payload)
        guard var payloadObject = try JSONSerialization.jsonObject(with: encodedPayload) as? [String: Any] else {
            throw PublishError.signingFailed
        }
        payloadObject["type"] = type
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        guard let payloadJson = String(data: payloadData, encoding: .utf8) else { throw PublishError.signingFailed }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var envelope = SignedEnvelope(
            clientId: pairing.clientId,
            counter: pairingStore.nextCounter(),
            timestamp: nowMs,
            type: type,
            payload: payloadJson,
            signature: "",
            validUntil: nowMs + ttlMs,
            wantsAck: wantsAck
        )
        envelope.signature = ClientControlCrypto.sign(secret: secret, canonical: envelope.canonicalString())

        let envelopeData = try JSONEncoder().encode(envelope)
        guard let envelopeObject = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any] else {
            throw PublishError.signingFailed
        }

        let document: [String: Any] = [
            "date": Self.documentDate,
            "utcOffset": 0,
            "app": "AAPS",
            "schemaVersion": 1,
            "envelope": envelopeObject,
        ]
        try await client.putSettings(identifier: "\(identifierPrefix)\(pairing.clientId)", document: document)
        return envelope.counter
    }
}
