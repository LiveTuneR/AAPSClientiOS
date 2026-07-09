import Foundation

enum PairingOfferFetcher {
    enum MatchResult: Equatable {
        case success(PairingPayload)
        case ambiguous
        case noMatch
    }

    static let offerIdentifierPrefix = "aaps_clientcontrol_offer_"

    static func match(offers: [PairingOffer], pin: String, now: Date) -> MatchResult {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        var matches: [PairingPayload] = []

        for offer in offers {
            if offer.expiresAt > 0, offer.expiresAt < nowMs { continue }
            guard let salt = Data(base64Encoded: offer.kdfSaltB64),
                  let iv = Data(base64Encoded: offer.ivB64),
                  let wrapped = Data(base64Encoded: offer.wrappedB64),
                  let plaintext = ClientControlPairingCrypto.unwrap(ciphertext: wrapped, pin: pin, salt: salt, iv: iv),
                  let payload = try? JSONDecoder().decode(PairingPayload.self, from: plaintext) else {
                continue
            }
            if payload.expiresAt > 0, payload.expiresAt < nowMs { continue }
            guard !payload.masterInstallId.isEmpty, !payload.clientId.isEmpty, !payload.secretHex.isEmpty else { continue }
            matches.append(payload)
        }

        switch matches.count {
        case 0: return .noMatch
        case 1: return .success(matches[0])
        default: return .ambiguous
        }
    }
}
