import XCTest
@testable import AAPSClientiOS

final class ClientControlModelsTests: XCTestCase {
    func test_signedEnvelopeCanonicalStringMatchesAndroidApsFormat() {
        let envelope = SignedEnvelope(
            clientId: "c1",
            counter: 1,
            timestamp: 1000,
            type: "hello",
            payload: "{\"protocolVersion\":1}",
            signature: "",
            validUntil: 9999,
            wantsAck: false
        )
        XCTAssertEqual(envelope.canonicalString(), "c1|1|1000|9999|false|hello|{\"protocolVersion\":1}")
    }

    func test_pairingOfferDecodesFromNsJson() throws {
        let json = #"{"schemaVersion":1,"clientId":"c1","expiresAt":123,"kdfSaltB64":"AAA=","ivB64":"BBB=","wrappedB64":"CCC="}"#
        let offer = try JSONDecoder().decode(PairingOffer.self, from: Data(json.utf8))
        XCTAssertEqual(offer.clientId, "c1")
        XCTAssertEqual(offer.expiresAt, 123)
    }

    func test_pairingPayloadDecodesFromDecryptedJson() throws {
        let json = #"{"v":1,"masterInstallId":"m1","clientId":"c1","secretHex":"aa","expiresAt":456}"#
        let payload = try JSONDecoder().decode(PairingPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.masterInstallId, "m1")
        XCTAssertEqual(payload.secretHex, "aa")
    }

    func test_ackEnvelopeCanonicalStringMatchesAndroidApsFormat() {
        let ack = AckEnvelope(
            clientId: "c1", commandCounter: 1, phase: .done, status: .ok,
            reason: nil, payload: nil, timestamp: 1000, signature: ""
        )
        XCTAssertEqual(ack.canonicalString(), "c1|1|Done|Ok|||1000")
    }

    func test_ackEnvelopeDecodesFromNsJson() throws {
        let json = #"{"clientId":"c1","commandCounter":2,"phase":"Executing","status":"Pending","timestamp":500,"signature":"deadbeef"}"#
        let ack = try JSONDecoder().decode(AckEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(ack.phase, .executing)
        XCTAssertEqual(ack.status, .pending)
        XCTAssertNil(ack.reason)
    }

    func test_bolusPreviewDecodesFromNsJson() throws {
        let json = #"""
        {"bolusId":123,"lines":[{"role":"NORMAL","text":"Scene: Exercise"}],"advisorApplies":false,"advisorLines":[]}
        """#
        let preview = try JSONDecoder().decode(BolusPreview.self, from: Data(json.utf8))
        XCTAssertEqual(preview.bolusId, 123)
        XCTAssertEqual(preview.lines.first?.role, "NORMAL")
        XCTAssertEqual(preview.lines.first?.text, "Scene: Exercise")
        XCTAssertFalse(preview.advisorApplies)
        XCTAssertNil(preview.wizardDetail)
    }

    func test_bolusPreviewDecodesWizardDetailWhenPresent() throws {
        let json = #"""
        {"bolusId":1,"lines":[],"advisorApplies":false,"advisorLines":[],"wizardDetail":{
            "totalInsulin":2.5,"carbs":40,"insulinFromBG":0.5,"insulinFromTrend":0,"insulinFromCOB":0.3,
            "insulinFromCarbs":1.7,"insulinFromBolusIOB":0,"insulinFromBasalIOB":0,"includeBolusIOB":true,
            "includeBasalIOB":true,"percentageCorrection":100,"cob":10,"tempTargetLabel":null,"ic":8,"sens":50
        }}
        """#
        let preview = try JSONDecoder().decode(BolusPreview.self, from: Data(json.utf8))
        XCTAssertEqual(preview.wizardDetail?.totalInsulin, 2.5)
        XCTAssertEqual(preview.wizardDetail?.carbs, 40)
    }

    func test_wizardPrepareEncodesAllFields() throws {
        let msg = ClientControlMessage.WizardPrepare(
            bg: 120, carbs: 40, percentage: 100, directCorrection: 0, carbTime: 0,
            useBg: true, useCob: true, useIob: true, useTt: true, useTrend: false,
            alarm: false, notes: "", eCarbsGrams: 0, eCarbsDelayMinutes: 0, eCarbsDurationHours: 0,
            profileName: nil
        )
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["bg"] as? Double, 120)
        XCTAssertEqual(json["carbs"] as? Int, 40)
        XCTAssertEqual(json["useBg"] as? Bool, true)
        XCTAssertEqual(json["useTrend"] as? Bool, false)
        XCTAssertNil(json["profileName"] as? String)
    }

    func test_scenePrepareEncodesSceneIdAndDuration() throws {
        let msg = ClientControlMessage.ScenePrepare(sceneId: "abc", durationMinutes: 30)
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["sceneId"] as? String, "abc")
        XCTAssertEqual(json["durationMinutes"] as? Int, 30)
    }

    func test_sceneCommitEncodesBolusId() throws {
        let msg = ClientControlMessage.SceneCommit(bolusId: 999)
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["bolusId"] as? Int64, 999)
    }
}
