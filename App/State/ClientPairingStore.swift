import Foundation

final class ClientPairingStore {
    private let keychain: KeychainStore
    private let counterDefaultsKey: String

    init(service: String = "clientcontrol.pairing") {
        self.keychain = KeychainStore(service: service, accessGroup: nil)
        self.counterDefaultsKey = "\(service).counterSent"
    }

    func currentPairing() -> MasterPairing? {
        guard let json = try? keychain.get(.clientControlPairing),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MasterPairing.self, from: data)
    }

    func pair(_ pairing: MasterPairing) {
        guard let data = try? JSONEncoder().encode(pairing),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        try? keychain.set(json, for: .clientControlPairing)
        UserDefaults.standard.set(Int64(0), forKey: counterDefaultsKey)
    }

    func unpair() {
        try? keychain.delete(.clientControlPairing)
        UserDefaults.standard.removeObject(forKey: counterDefaultsKey)
    }

    func nextCounter() -> Int64 {
        let current = Int64(UserDefaults.standard.integer(forKey: counterDefaultsKey))
        let next = current + 1
        UserDefaults.standard.set(next, forKey: counterDefaultsKey)
        return next
    }
}
