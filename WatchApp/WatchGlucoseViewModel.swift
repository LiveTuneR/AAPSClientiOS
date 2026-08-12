import Combine
import Foundation

@MainActor
final class WatchGlucoseViewModel: ObservableObject {
    @Published private(set) var payload: WatchGlucosePayload?

    private let store = WatchPayloadStore()
    private var observer: NSObjectProtocol?

    init() {
        payload = store.load()
        observer = NotificationCenter.default.addObserver(
            forName: WatchPayloadStore.payloadUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.payload = self?.store.load() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        payload = store.load()
        WatchConnectivityReceiver.shared.requestLatest()
    }
}
