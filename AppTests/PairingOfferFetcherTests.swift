import XCTest
@testable import AAPSClientiOS

final class PairingOfferFetcherTests: XCTestCase {
    func test_findsMatchingOfferWithCorrectPin() throws {
        let offer = try makeOffer(pin: "12345678")
        let result = PairingOfferFetcher.match(offers: [offer], pin: "12345678", now: Date())
        guard case .success(let matched) = result else { return XCTFail("expected success") }
        XCTAssertEqual(matched.clientId, "c1")
    }

    func test_wrongPinReturnsNoMatch() throws {
        let offer = try makeOffer(pin: "12345678")
        let result = PairingOfferFetcher.match(offers: [offer], pin: "00000000", now: Date())
        guard case .noMatch = result else { return XCTFail("expected noMatch") }
    }

    func test_expiredOfferIsSkipped() throws {
        let offer = PairingOffer(schemaVersion: 1, clientId: "c1", expiresAt: 1, kdfSaltB64: "", ivB64: "", wrappedB64: "")
        let result = PairingOfferFetcher.match(offers: [offer], pin: "12345678", now: Date(timeIntervalSince1970: 1000))
        guard case .noMatch = result else { return XCTFail("expected noMatch for expired offer") }
    }

    private func makeOffer(pin: String) throws -> PairingOffer {
        let salt = ClientControlPairingCrypto.newSalt()
        let iv = ClientControlPairingCrypto.newIV()
        let payload = PairingPayload(v: 1, masterInstallId: "m1", clientId: "c1", secretHex: "aabb", expiresAt: 0)
        let payloadJson = try JSONEncoder().encode(payload)
        let wrapped = try ClientControlPairingCrypto.wrap(plaintext: payloadJson, pin: pin, salt: salt, iv: iv)
        return PairingOffer(
            schemaVersion: 1,
            clientId: "c1",
            expiresAt: 0,
            kdfSaltB64: salt.base64EncodedString(),
            ivB64: iv.base64EncodedString(),
            wrappedB64: wrapped.base64EncodedString()
        )
    }
}
