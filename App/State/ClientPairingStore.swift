import Foundation

final class ClientPairingStore {
    private let keychain: KeychainStore
    private let counterDefaultsKey: String
    private let pairedAtDefaultsKey: String

    init(service: String = "clientcontrol.pairing") {
        self.keychain = KeychainStore(service: service, accessGroup: nil)
        self.counterDefaultsKey = "\(service).counterSent"
        self.pairedAtDefaultsKey = "\(service).pairedAt"
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
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pairedAtDefaultsKey)
    }

    func unpair() {
        try? keychain.delete(.clientControlPairing)
        UserDefaults.standard.removeObject(forKey: counterDefaultsKey)
        UserDefaults.standard.removeObject(forKey: pairedAtDefaultsKey)
    }

    func nextCounter() -> Int64 {
        let current = Int64(UserDefaults.standard.integer(forKey: counterDefaultsKey))
        let next = current + 1
        UserDefaults.standard.set(next, forKey: counterDefaultsKey)
        return next
    }

    /// When the current pairing was created. Used by `OrphanDetector`'s race-window guard —
    /// mirrors AndroidAPS's `NsClientControlPairedAt` preference.
    func pairedAt() -> Date? {
        let raw = UserDefaults.standard.double(forKey: pairedAtDefaultsKey)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }
}
