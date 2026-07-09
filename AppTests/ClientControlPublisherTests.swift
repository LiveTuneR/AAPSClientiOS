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
}
