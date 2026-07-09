import Foundation

/// Pure decision logic mirroring AndroidAPS `OrphanDetector.kt`'s `onSettingsDoc`. Given the
/// latest `authorizedClients.clientIds` roster from a `settings/aaps` doc, decides whether this
/// client's pairing is still valid. No side effects (no notifications, no store mutation) — the
/// caller (see `AppStore` wiring) turns `.orphaned` into user-visible state.
enum OrphanDetector {
    enum Verdict: Equatable {
        /// No roster in this doc (older master, or field genuinely absent) — nothing to conclude.
        case noSignal
        /// Own clientId is present in the roster — pairing confirmed valid.
        case authorized
        /// Own clientId is missing, but the doc predates pairing + the grace window — the master
        /// likely hasn't republished the roster yet. Not a verdict; caller should keep the prior state.
        case deferred
        /// Own clientId is missing, past the grace window — the master revoked (or never knew about)
        /// this pairing.
        case orphaned
    }

    /// Slack between pair and the master's roster republish landing on this client — matches
    /// AndroidAPS's `OrphanDetector.POST_PAIRING_GRACE_MS` exactly (60s), sized to absorb the
    /// master's 5s debounce plus HTTP/WS propagation delay and clock skew.
    static let defaultGracePeriodMs: Int64 = 60_000

    static func evaluate(
        ownClientId: String,
        roster: [String]?,
        docSrvModifiedMs: Int64,
        pairedAtMs: Int64,
        nowMs: Int64,
        gracePeriodMs: Int64 = defaultGracePeriodMs
    ) -> Verdict {
        guard let roster else { return .noSignal }
        if roster.contains(ownClientId) { return .authorized }
        if pairedAtMs > 0, docSrvModifiedMs > 0, docSrvModifiedMs < pairedAtMs + gracePeriodMs {
            return .deferred
        }
        return .orphaned
    }
}
