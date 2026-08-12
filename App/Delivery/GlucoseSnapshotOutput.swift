import Foundation

@MainActor
protocol GlucoseSnapshotOutput: AnyObject {
    func publish(snapshot: GlucoseSnapshot, config: DisplayConfig, force: Bool)
}

@MainActor
final class GlucoseDeliveryCoordinator: GlucoseSnapshotOutput {
    static let shared = GlucoseDeliveryCoordinator()

    private let outputs: [GlucoseSnapshotOutput]

    init(outputs: [GlucoseSnapshotOutput]? = nil) {
        self.outputs = outputs ?? [PhoneWatchConnectivity.shared, CalendarGlucoseBridge.shared]
    }

    func start() {
        PhoneWatchConnectivity.shared.start()
    }

    func publish(snapshot: GlucoseSnapshot, config: DisplayConfig, force: Bool) {
        outputs.forEach { $0.publish(snapshot: snapshot, config: config, force: force) }
    }
}
