import ActivityKit
import Foundation

/// Starts/stops/updates the glucose Live Activity. Best-effort: updates only
/// fire while the app process is alive (foreground or background refresh). No
/// push server, so the activity goes stale when the app is not running.
@available(iOS 16.1, *)
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<GlucoseActivityAttributes>?

    var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(with state: GlucoseActivityAttributes.ContentState) {
        guard isSupported, activity == nil else { return }
        activity = try? Activity.request(
            attributes: GlucoseActivityAttributes(),
            contentState: state
        )
    }

    func update(_ state: GlucoseActivityAttributes.ContentState) {
        Task { await activity?.update(using: state) }
    }

    func stop() {
        Task {
            await activity?.end(dismissalPolicy: .immediate)
            activity = nil
        }
    }

    var isRunning: Bool { activity != nil }
}
