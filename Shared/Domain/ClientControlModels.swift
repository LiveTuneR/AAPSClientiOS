import Foundation

struct PairingOffer: Codable, Equatable {
    let schemaVersion: Int
    let clientId: String
    let expiresAt: Int64
    let kdfSaltB64: String
    let ivB64: String
    let wrappedB64: String
}

struct PairingPayload: Codable, Equatable {
    let v: Int
    let masterInstallId: String
    let clientId: String
    let secretHex: String
    let expiresAt: Int64
}

struct MasterPairing: Codable, Equatable {
    let masterInstallId: String
    let clientId: String
    let secretHex: String
}

struct SignedEnvelope: Codable, Equatable {
    let clientId: String
    let counter: Int64
    let timestamp: Int64
    let type: String
    let payload: String
    var signature: String
    var validUntil: Int64 = .max
    var wantsAck: Bool = false

    func canonicalString() -> String {
        "\(clientId)|\(counter)|\(timestamp)|\(validUntil)|\(wantsAck)|\(type)|\(payload)"
    }
}

enum ClientControlMessage {
    struct Hello: Codable {
        var protocolVersion: Int = 1
        static let type = "hello"
    }

    struct Ping: Codable {
        static let type = "ping"
    }
}
