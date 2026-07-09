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
}
