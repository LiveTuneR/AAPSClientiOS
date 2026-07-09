import XCTest
@testable import AAPSClientiOS

final class ClientControlPublisherTests: XCTestCase {
    func test_sendHelloPostsSignedEnvelopeToCorrectIdentifier() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(
            masterInstallId: "m1",
            clientId: "c1",
            secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())
        ))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        try await publisher.sendHello()

        XCTAssertEqual(mock.putSettingsCalls.first?.identifier, "aaps_clientcontrol_hello_c1")
    }

    func test_sendHelloFailsGracefullyWhenUnpaired() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        do {
            try await publisher.sendHello()
            XCTFail("expected notPaired error")
        } catch ClientControlPublisher.PublishError.notPaired {
        }
    }

    func test_sendPingSetsWantsAckTrue() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        try await publisher.sendPing()

        let doc = try XCTUnwrap(mock.putSettingsCalls.first?.document)
        let envelope = try XCTUnwrap(doc["envelope"] as? [String: Any])
        XCTAssertEqual(envelope["wantsAck"] as? Bool, true)
    }

    func test_fetchAckReturnsVerifiedEnvelopeOnMatchingCounter() async throws {
        let mock = FixtureNightscoutClient()
        let secret = ClientControlCrypto.newSecretBytes()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(secret)))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        var ack = AckEnvelope(clientId: "c1", commandCounter: 1, phase: .done, status: .ok, reason: nil, payload: nil, timestamp: Int64(Date().timeIntervalSince1970 * 1000), signature: "")
        ack.signature = ClientControlCrypto.sign(secret: secret, canonical: ack.canonicalString())
        let ackData = try JSONEncoder().encode(ack)
        let ackJson = try JSONSerialization.jsonObject(with: ackData) as! [String: Any]
        mock.settingsDocumentOverride["aaps_clientcontrol_ack_c1"] = try NsMapping.settingsDocument(
            from: JSONSerialization.data(withJSONObject: ["status": 200, "result": ["identifier": "aaps_clientcontrol_ack_c1", "date": 1, "utcOffset": 0, "app": "AAPS", "schemaVersion": 1, "ack": ackJson]]),
            identifier: "aaps_clientcontrol_ack_c1"
        )

        let result = try await publisher.fetchAck(expectedCounter: 1)
        XCTAssertEqual(result, .terminal(.ok, reason: nil))
    }

    func test_fetchAckRejectsBadSignature() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        let ack = AckEnvelope(clientId: "c1", commandCounter: 1, phase: .done, status: .ok, reason: nil, payload: nil, timestamp: Int64(Date().timeIntervalSince1970 * 1000), signature: "not-a-real-signature")
        let ackData = try JSONEncoder().encode(ack)
        let ackJson = try JSONSerialization.jsonObject(with: ackData) as! [String: Any]
        mock.settingsDocumentOverride["aaps_clientcontrol_ack_c1"] = try NsMapping.settingsDocument(
            from: JSONSerialization.data(withJSONObject: ["status": 200, "result": ["identifier": "aaps_clientcontrol_ack_c1", "date": 1, "utcOffset": 0, "app": "AAPS", "schemaVersion": 1, "ack": ackJson]]),
            identifier: "aaps_clientcontrol_ack_c1"
        )

        let result = try await publisher.fetchAck(expectedCounter: 1)
        XCTAssertEqual(result, .invalidSignature)
    }

    func test_fetchAckIgnoresStaleCounter() async throws {
        let mock = FixtureNightscoutClient()
        let secret = ClientControlCrypto.newSecretBytes()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(secret)))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        var ack = AckEnvelope(clientId: "c1", commandCounter: 1, phase: .done, status: .ok, reason: nil, payload: nil, timestamp: Int64(Date().timeIntervalSince1970 * 1000), signature: "")
        ack.signature = ClientControlCrypto.sign(secret: secret, canonical: ack.canonicalString())
        let ackData = try JSONEncoder().encode(ack)
        let ackJson = try JSONSerialization.jsonObject(with: ackData) as! [String: Any]
        mock.settingsDocumentOverride["aaps_clientcontrol_ack_c1"] = try NsMapping.settingsDocument(
            from: JSONSerialization.data(withJSONObject: ["status": 200, "result": ["identifier": "aaps_clientcontrol_ack_c1", "date": 1, "utcOffset": 0, "app": "AAPS", "schemaVersion": 1, "ack": ackJson]]),
            identifier: "aaps_clientcontrol_ack_c1"
        )

        let result = try await publisher.fetchAck(expectedCounter: 2)
        XCTAssertEqual(result, .pending)
    }
}
