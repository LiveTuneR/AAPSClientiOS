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

    func sendHello() async throws {
        try await send(
            type: ClientControlMessage.Hello.type,
            payload: ClientControlMessage.Hello(),
            identifierPrefix: "aaps_clientcontrol_hello_"
        )
    }

    func sendPing() async throws {
        try await send(
            type: ClientControlMessage.Ping.type,
            payload: ClientControlMessage.Ping(),
            identifierPrefix: "aaps_clientcontrol_cmd_ping_"
        )
    }

    private func send<T: Encodable>(type: String, payload: T, identifierPrefix: String) async throws {
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
            wantsAck: false
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
    }
}
