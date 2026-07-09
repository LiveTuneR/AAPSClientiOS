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

/// Mirrors AndroidAPS `AckEnvelope.kt` exactly — the master's signed acknowledgement for a
/// single client-control command, written to `aaps_clientcontrol_ack_<clientId>` (overwritten
/// in place) under a top-level `"ack"` field. Field order in `canonicalString()` is the wire
/// contract for HMAC verification — do not reorder.
struct AckEnvelope: Codable, Equatable {
    let clientId: String
    let commandCounter: Int64
    let phase: AckPhase
    let status: AckStatus
    let reason: String?
    let payload: String?
    let timestamp: Int64
    var signature: String

    func canonicalString() -> String {
        "\(clientId)|\(commandCounter)|\(phase.rawValue)|\(status.rawValue)|\(reason ?? "")|\(payload ?? "")|\(timestamp)"
    }
}

/// Matches Kotlin's `@SerialName`-annotated enum cases exactly (case-sensitive on the wire).
enum AckPhase: String, Codable {
    case executing = "Executing"
    case done = "Done"
    case delivery = "Delivery"
}

enum AckStatus: String, Codable {
    case pending = "Pending"
    case ok = "Ok"
    case failed = "Failed"
    case expired = "Expired"
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
