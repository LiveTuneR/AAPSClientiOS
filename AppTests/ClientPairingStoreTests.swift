import XCTest
@testable import AAPSClientiOS

final class ClientPairingStoreTests: XCTestCase {
    func test_pairThenLoadRoundTrips() throws {
        let store = ClientPairingStore(service: "test.clientcontrol.\(UUID().uuidString)")
        defer { store.unpair() }

        XCTAssertNil(store.currentPairing())

        let pairing = MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: "aabbcc")
        store.pair(pairing)

        XCTAssertEqual(store.currentPairing(), pairing)
    }

    func test_unpairClearsStoredPairing() throws {
        let store = ClientPairingStore(service: "test.clientcontrol.\(UUID().uuidString)")
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: "aabbcc"))
        store.unpair()
        XCTAssertNil(store.currentPairing())
    }

    func test_counterIncrementsMonotonically() throws {
        let store = ClientPairingStore(service: "test.clientcontrol.\(UUID().uuidString)")
        defer { store.unpair() }
        store.pair(MasterPairing(masterInstallId: "m1", clientId: "c1", secretHex: "aabbcc"))

        XCTAssertEqual(store.nextCounter(), 1)
        XCTAssertEqual(store.nextCounter(), 2)
    }
}
