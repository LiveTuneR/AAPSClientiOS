import Foundation
import WatchConnectivity
import WidgetKit

final class WatchConnectivityReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchConnectivityReceiver()

    private let session: WCSession?
    private let store = WatchPayloadStore()

    override private init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
    }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        if let data = session.receivedApplicationContext[WatchGlucosePayload.dataKey] as? Data {
            accept(data, source: "initial-context")
        }
    }

    func requestLatest() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["aaps.watch.requestLatest": true], replyHandler: { [weak self] reply in
            guard let data = reply[WatchGlucosePayload.dataKey] as? Data else { return }
            self?.accept(data, source: "requested")
        }, errorHandler: { [weak self] error in
            self?.store.record("request-failed", details: error.localizedDescription)
        })
    }

    private func accept(_ data: Data, source: String) {
        guard let payload = try? JSONDecoder().decode(WatchGlucosePayload.self, from: data),
              payload.schemaVersion == WatchGlucosePayload.currentSchemaVersion else {
            store.record("decode-failed", details: source)
            return
        }
        let saved = store.save(payload)
        store.record(saved ? "accepted" : "stale-ignored", sequence: payload.sequence, details: source)
        guard saved else { return }
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WatchPayloadStore.payloadUpdated, object: nil)
        }
        sendBackgroundAck(for: payload.sequence)
    }

    private func ackData(for sequence: Int64) -> Data? {
        let ack = WatchDeliveryAck(
            sequence: sequence,
            receivedAt: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        return try? JSONEncoder().encode(ack)
    }

    private func sendBackgroundAck(for sequence: Int64) {
        guard let session, let data = ackData(for: sequence) else { return }
        do {
            try session.updateApplicationContext([WatchDeliveryAck.dataKey: data])
        } catch {
            store.record("ack-failed", sequence: sequence, details: error.localizedDescription)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        store.record(
            activationState == .activated ? "session-activated" : "session-failed",
            details: error?.localizedDescription
        )
        if activationState == .activated,
           let data = session.receivedApplicationContext[WatchGlucosePayload.dataKey] as? Data {
            accept(data, source: "activation-context")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchGlucosePayload.dataKey] as? Data else { return }
        accept(data, source: "context")
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchGlucosePayload.dataKey] as? Data else { return }
        accept(data, source: "user-info")
    }

    func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        accept(messageData, source: "live")
        if let payload = try? JSONDecoder().decode(WatchGlucosePayload.self, from: messageData),
           let data = ackData(for: payload.sequence) {
            replyHandler(data)
        } else {
            replyHandler(Data())
        }
    }
}
