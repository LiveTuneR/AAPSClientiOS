import Foundation
import WatchConnectivity

final class PhoneWatchConnectivity: NSObject, GlucoseSnapshotOutput, @unchecked Sendable {
    static let shared = PhoneWatchConnectivity()

    private let session: WCSession?
    private let lock = NSLock()
    private var latestData: Data?
    private var lastPublishedSequence: Int64?
    private var lastComplicationTransfer = Date.distantPast
    private let complicationFallbackInterval: TimeInterval = 30 * 60

    override private init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    @MainActor
    func start() {
        guard let session else {
            DeliveryDiagnostics.shared.record(channel: "watch", state: "unsupported")
            return
        }
        session.delegate = self
        session.activate()
    }

    @MainActor
    func publish(snapshot: GlucoseSnapshot, config: DisplayConfig, force: Bool) {
        let payload = WatchGlucosePayload(snapshot: snapshot, config: config)
        guard force || payload.sequence != lastPublishedSequence else { return }
        guard let data = try? JSONEncoder().encode(payload) else {
            DeliveryDiagnostics.shared.record(
                channel: "watch", state: "encode-failed", sequence: payload.sequence
            )
            return
        }

        lock.lock()
        latestData = data
        lastPublishedSequence = payload.sequence
        lock.unlock()

        guard let session, session.activationState == .activated else {
            session?.activate()
            DeliveryDiagnostics.shared.record(
                channel: "watch", state: "session-inactive", sequence: payload.sequence
            )
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            DeliveryDiagnostics.shared.record(
                channel: "watch", state: "not-installed", sequence: payload.sequence
            )
            return
        }

        do {
            try session.updateApplicationContext([WatchGlucosePayload.dataKey: data])
            DeliveryDiagnostics.shared.record(
                channel: "watch", state: "context-updated", sequence: payload.sequence
            )
        } catch {
            DeliveryDiagnostics.shared.record(
                channel: "watch", state: "context-failed", sequence: payload.sequence,
                details: error.localizedDescription
            )
        }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: { reply in
                Self.recordReply(reply, expectedSequence: payload.sequence, channel: "watch-live")
            }, errorHandler: { error in
                DeliveryDiagnostics.shared.record(
                    channel: "watch-live", state: "send-failed", sequence: payload.sequence,
                    details: error.localizedDescription
                )
            })
            DeliveryDiagnostics.shared.record(
                channel: "watch-live", state: "sent", sequence: payload.sequence
            )
        } else {
            session.transferUserInfo([WatchGlucosePayload.dataKey: data])
            DeliveryDiagnostics.shared.record(
                channel: "watch-background", state: "queued", sequence: payload.sequence
            )
        }

        if session.isComplicationEnabled,
           force || Date().timeIntervalSince(lastComplicationTransfer) >= complicationFallbackInterval {
            session.transferCurrentComplicationUserInfo([WatchGlucosePayload.dataKey: data])
            lastComplicationTransfer = Date()
            DeliveryDiagnostics.shared.record(
                channel: "watch-complication", state: "queued", sequence: payload.sequence,
                details: "remaining=\(session.remainingComplicationUserInfoTransfers)"
            )
        }
    }

    private func currentData() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return latestData
    }

    private static func recordReply(_ data: Data, expectedSequence: Int64, channel: String) {
        guard let ack = try? JSONDecoder().decode(WatchDeliveryAck.self, from: data) else {
            DeliveryDiagnostics.shared.record(
                channel: channel, state: "invalid-ack", sequence: expectedSequence
            )
            return
        }
        let latency = max(0, Int64(Date().timeIntervalSince1970 * 1_000) - ack.receivedAt)
        DeliveryDiagnostics.shared.record(
            channel: channel,
            state: ack.sequence == expectedSequence ? "acknowledged" : "stale-ack",
            sequence: ack.sequence,
            details: "callbackLatencyMs=\(latency)"
        )
    }
}

extension PhoneWatchConnectivity: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DeliveryDiagnostics.shared.record(
            channel: "watch", state: activationState == .activated ? "activated" : "activation-failed",
            details: error?.localizedDescription
        )
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        recordBackgroundAck(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        recordBackgroundAck(userInfo)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["aaps.watch.requestLatest"] as? Bool == true,
              let data = currentData() else {
            replyHandler(["error": "no-data"])
            return
        }
        replyHandler([WatchGlucosePayload.dataKey: data])
    }

    private func recordBackgroundAck(_ dictionary: [String: Any]) {
        guard let data = dictionary[WatchDeliveryAck.dataKey] as? Data,
              let ack = try? JSONDecoder().decode(WatchDeliveryAck.self, from: data) else { return }
        let latency = max(0, Int64(Date().timeIntervalSince1970 * 1_000) - ack.receivedAt)
        DeliveryDiagnostics.shared.record(
            channel: "watch-background", state: "acknowledged", sequence: ack.sequence,
            details: "callbackLatencyMs=\(latency)"
        )
    }
}
