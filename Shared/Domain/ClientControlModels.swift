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

    /// Asks the master to PREPARE a manual wizard-computed bolus from these raw inputs — the master
    /// recomputes the dose on its OWN live profile/COB/IOB, constraint-caps it, and returns the full
    /// breakdown in `BolusPreview.wizardDetail`. This app NEVER sends the matching commit — see the
    /// plan header for why (permanent, deliberate bolus exclusion). `bg`/`carbs` mirror the master's
    /// own manual bolus-wizard dialog inputs exactly.
    struct WizardPrepare: Codable {
        let bg: Double
        let carbs: Int
        let percentage: Int
        let directCorrection: Double
        let carbTime: Int
        let useBg: Bool
        let useCob: Bool
        let useIob: Bool
        let useTt: Bool
        let useTrend: Bool
        let alarm: Bool
        let notes: String
        let eCarbsGrams: Int
        let eCarbsDelayMinutes: Int
        let eCarbsDurationHours: Int
        let profileName: String?
        static let type = "wizard_prepare"
    }

    /// Asks the master to PREPARE activating the named scene — validated + parked, returns a
    /// `BolusPreview` in the signed ack. Nothing activates until a matching `SceneCommit`.
    /// `durationMinutes: nil` uses the scene's own stored default duration.
    struct ScenePrepare: Codable {
        let sceneId: String
        let durationMinutes: Int?
        static let type = "scene_prepare"
    }

    /// Confirms a prepared scene: the master activates the parked scene matching `bolusId` exactly
    /// once (a re-sent commit safely no-ops on an already-consumed id).
    struct SceneCommit: Codable {
        let bolusId: Int64
        static let type = "scene_commit"
    }

    /// Deactivates whatever scene is currently active. `triggerChain: true` mirrors the master's own
    /// "Skip to <chain target>" — the master resolves the chain target FRESH at receipt time using
    /// its own current config, so a stale client view can never trigger an unintended scene.
    struct SceneStop: Codable {
        var triggerChain: Bool = false
        static let type = "scene_stop"
    }
}

/// The master's computed preview for any two-step prepare→commit action (scene/wizard/bolus/batch),
/// carried in `AckEnvelope.payload` for a `..Prepare` ack. Mirrors AndroidAPS `BolusPreview.kt`
/// exactly — despite the name, this is the generic "prepared action" envelope reused across every
/// prepare type on the master, not bolus-specific.
struct BolusPreview: Codable, Equatable {
    let bolusId: Int64
    let lines: [ConfirmationLineDto]
    let advisorApplies: Bool
    let advisorLines: [ConfirmationLineDto]
    let wizardDetail: WizardDetailDto?

    init(bolusId: Int64, lines: [ConfirmationLineDto] = [], advisorApplies: Bool = false, advisorLines: [ConfirmationLineDto] = [], wizardDetail: WizardDetailDto? = nil) {
        self.bolusId = bolusId
        self.lines = lines
        self.advisorApplies = advisorApplies
        self.advisorLines = advisorLines
        self.wizardDetail = wizardDetail
    }
}

/// One confirmation line — the master's already-localized, color-coded wizard/scene confirmation text.
/// Mirrors AndroidAPS `ConfirmationLineDto.kt`.
struct ConfirmationLineDto: Codable, Equatable {
    let role: String
    let text: String
}

/// Raw wizard calculation breakdown, present only on `WizardPrepare`/`BolusPrepare` acks (absent for
/// scene/batch-only prepares, hence optional on `BolusPreview`). Mirrors AndroidAPS `WizardDetailDto.kt`.
struct WizardDetailDto: Codable, Equatable {
    let totalInsulin: Double
    let carbs: Int
    let insulinFromBG: Double
    let insulinFromTrend: Double
    let insulinFromCOB: Double
    let insulinFromCarbs: Double
    let insulinFromBolusIOB: Double
    let insulinFromBasalIOB: Double
    let includeBolusIOB: Bool
    let includeBasalIOB: Bool
    let percentageCorrection: Int
    let cob: Double
    let tempTargetLabel: String?
    let ic: Double
    let sens: Double
}
