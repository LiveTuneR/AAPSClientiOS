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
        let payload = try XCTUnwrap(envelope["payload"] as? String)
        let payloadObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payloadObject["type"] as? String, "ping")
        XCTAssertEqual((envelope["validUntil"] as? Int64) ?? Int64(envelope["validUntil"] as? Int ?? 0),
                       ((envelope["timestamp"] as? Int64) ?? Int64(envelope["timestamp"] as? Int ?? 0)) + ClientControlPublisher.pingTTL)
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
        XCTAssertEqual(result, .terminal(.ok, reason: nil, payload: nil))
    }

    func test_sendScenePrepareUsesCorrectIdentifierAndType() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        try await publisher.sendScenePrepare(sceneId: "sleep", durationMinutes: nil)

        let call = try XCTUnwrap(mock.putSettingsCalls.first)
        XCTAssertEqual(call.identifier, "aaps_clientcontrol_cmd_scene_prepare_c1")
        let envelope = try XCTUnwrap(call.document["envelope"] as? [String: Any])
        XCTAssertEqual(envelope["type"] as? String, "scene_prepare")
        XCTAssertEqual(envelope["wantsAck"] as? Bool, true)
    }

    func test_sendSceneCommitUsesCorrectIdentifierAndType() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        try await publisher.sendSceneCommit(bolusId: 42)

        let call = try XCTUnwrap(mock.putSettingsCalls.first)
        XCTAssertEqual(call.identifier, "aaps_clientcontrol_cmd_scene_commit_c1")
        let envelope = try XCTUnwrap(call.document["envelope"] as? [String: Any])
        XCTAssertEqual(envelope["type"] as? String, "scene_commit")
    }

    func test_sendSceneStopUsesCorrectIdentifierAndType() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        try await publisher.sendSceneStop(triggerChain: false)

        let call = try XCTUnwrap(mock.putSettingsCalls.first)
        XCTAssertEqual(call.identifier, "aaps_clientcontrol_cmd_scene_stop_c1")
        let envelope = try XCTUnwrap(call.document["envelope"] as? [String: Any])
        XCTAssertEqual(envelope["type"] as? String, "scene_stop")
        XCTAssertEqual(envelope["wantsAck"] as? Bool, false)
    }

    func test_sendBatchPrepareIncludesKotlinDiscriminatorAndAction() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(
            masterInstallId: "m1", clientId: "c1",
            secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())
        ))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)
        var action = BatchActionDto(type: .tempTarget)
        action.reason = "ACTIVITY"
        action.lowMgdl = 120
        action.highMgdl = 120
        action.durationMinutes = 60

        try await publisher.sendBatchPrepare([action])

        let call = try XCTUnwrap(mock.putSettingsCalls.first)
        XCTAssertEqual(call.identifier, "aaps_clientcontrol_cmd_batch_prepare_c1")
        XCTAssertEqual(call.document["date"] as? Int64, ClientControlPublisher.documentDate)
        let envelope = try XCTUnwrap(call.document["envelope"] as? [String: Any])
        let payload = try XCTUnwrap(envelope["payload"] as? String)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "batch_prepare")
        let actions = try XCTUnwrap(object["actions"] as? [[String: Any]])
        XCTAssertEqual(actions.first?["type"] as? String, "temp_target")
        XCTAssertEqual(actions.first?["durationMinutes"] as? Int, 60)
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

    func test_fetchAckRejectsTimestampOutsideSkewWindow() async throws {
        let mock = FixtureNightscoutClient()
        let secret = ClientControlCrypto.newSecretBytes()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(secret)))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        // Signature is otherwise valid, but the ack was (supposedly) written 20 minutes ago —
        // well outside the 5-minute default skew window `timestampWithinSkew` enforces.
        let staleTimestamp = Int64(Date().addingTimeInterval(-20 * 60).timeIntervalSince1970 * 1000)
        var ack = AckEnvelope(clientId: "c1", commandCounter: 1, phase: .done, status: .ok, reason: nil, payload: nil, timestamp: staleTimestamp, signature: "")
        ack.signature = ClientControlCrypto.sign(secret: secret, canonical: ack.canonicalString())
        let ackData = try JSONEncoder().encode(ack)
        let ackJson = try JSONSerialization.jsonObject(with: ackData) as! [String: Any]
        mock.settingsDocumentOverride["aaps_clientcontrol_ack_c1"] = try NsMapping.settingsDocument(
            from: JSONSerialization.data(withJSONObject: ["status": 200, "result": ["identifier": "aaps_clientcontrol_ack_c1", "date": 1, "utcOffset": 0, "app": "AAPS", "schemaVersion": 1, "ack": ackJson]]),
            identifier: "aaps_clientcontrol_ack_c1"
        )

        let result = try await publisher.fetchAck(expectedCounter: 1)
        XCTAssertEqual(result, .staleTimestamp)
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

    func test_fetchAckExposesPreviewPayloadOnTerminalOk() async throws {
        let mock = FixtureNightscoutClient()
        let secret = ClientControlCrypto.newSecretBytes()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(secret)))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        let previewJson = #"{"bolusId":42,"lines":[{"role":"NORMAL","text":"Scene: Sleep"}],"advisorApplies":false,"advisorLines":[]}"#
        var ack = AckEnvelope(clientId: "c1", commandCounter: 1, phase: .done, status: .ok, reason: nil, payload: previewJson, timestamp: Int64(Date().timeIntervalSince1970 * 1000), signature: "")
        ack.signature = ClientControlCrypto.sign(secret: secret, canonical: ack.canonicalString())
        let ackData = try JSONEncoder().encode(ack)
        let ackJson = try JSONSerialization.jsonObject(with: ackData) as! [String: Any]
        mock.settingsDocumentOverride["aaps_clientcontrol_ack_c1"] = try NsMapping.settingsDocument(
            from: JSONSerialization.data(withJSONObject: ["status": 200, "result": ["identifier": "aaps_clientcontrol_ack_c1", "date": 1, "utcOffset": 0, "app": "AAPS", "schemaVersion": 1, "ack": ackJson]]),
            identifier: "aaps_clientcontrol_ack_c1"
        )

        let result = try await publisher.fetchAck(expectedCounter: 1)
        guard case .terminal(.ok, _, let payload) = result else { return XCTFail("expected terminal Ok with payload") }
        let preview = try JSONDecoder().decode(BolusPreview.self, from: Data(payload!.utf8))
        XCTAssertEqual(preview.bolusId, 42)
    }

    func test_sendWizardPrepareUsesCorrectIdentifierAndType() async throws {
        let mock = FixtureNightscoutClient()
        let store = ClientPairingStore(service: "test.\(UUID().uuidString)")
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: ClientControlCrypto.bytesToHex(ClientControlCrypto.newSecretBytes())))
        let publisher = ClientControlPublisher(client: mock, pairingStore: store)

        let inputs = ClientControlMessage.WizardPrepare(
            bg: 120, carbs: 40, percentage: 100, directCorrection: 0, carbTime: 0,
            useBg: true, useCob: true, useIob: true, useTt: true, useTrend: true,
            alarm: false, notes: "", eCarbsGrams: 0, eCarbsDelayMinutes: 0, eCarbsDurationHours: 0,
            profileName: nil
        )
        try await publisher.sendWizardPrepare(inputs)

        let call = try XCTUnwrap(mock.putSettingsCalls.first)
        XCTAssertEqual(call.identifier, "aaps_clientcontrol_cmd_wizard_prepare_c1")
        let envelope = try XCTUnwrap(call.document["envelope"] as? [String: Any])
        XCTAssertEqual(envelope["type"] as? String, "wizard_prepare")
        XCTAssertEqual(envelope["wantsAck"] as? Bool, true)
    }
}
