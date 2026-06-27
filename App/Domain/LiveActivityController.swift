import ActivityKit
import Foundation
import os

/// Starts/stops/updates the glucose Live Activity. Best-effort: updates only
/// fire while the app process is alive (foreground or background refresh). No
/// push server, so the activity goes stale when the app is not running.
@available(iOS 16.1, *)
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<GlucoseActivityAttributes>?
    private let log = Logger(subsystem: "com.nightaps.aapsclientios", category: "LiveActivity")

    private init() {
        reattach()
    }

    var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Re-bind to an activity that survived a previous launch. `Activity.activities`
    /// can still be empty at the instant the singleton is first created — ActivityKit
    /// populates it asynchronously shortly after launch — so a one-shot re-attach in
    /// `init` can lose the race and leave the reference nil forever, silently dropping
    /// every `update()` while a stale activity stays frozen on screen. We therefore
    /// re-attempt on demand before each update until the binding succeeds.
    @discardableResult
    private func reattach() -> Bool {
        if activity == nil {
            activity = Activity<GlucoseActivityAttributes>.activities.first
        }
        return activity != nil
    }

    @discardableResult
    func start(with state: GlucoseActivityAttributes.ContentState) -> Bool {
        guard isSupported else { return false }
        if reattach() { update(state); return true }
        do {
            let staleDate = Date().addingTimeInterval(15 * 60)
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: GlucoseActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: staleDate)
                )
            } else {
                activity = try Activity.request(
                    attributes: GlucoseActivityAttributes(),
                    contentState: state
                )
            }
            log.info("started live activity")
            DebugLog.log("LA.start created id=\(String(describing: activity?.id.suffix(4))) mgdl=\(state.mgdl)")
            return true
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            DebugLog.log("LA.start FAILED \(error.localizedDescription)")
            return false
        }
    }

    func update(_ state: GlucoseActivityAttributes.ContentState) {
        guard reattach() else {
            log.debug("update dropped — no live activity to bind")
            DebugLog.log("LA.update DROPPED (no activity)")
            return
        }
        let bound = activity
        Task {
            let staleDate = Date().addingTimeInterval(15 * 60)
            if #available(iOS 16.2, *) {
                await bound?.update(ActivityContent(state: state, staleDate: staleDate))
            } else {
                await bound?.update(using: state)
            }
            if #available(iOS 16.2, *) {
                let held = bound?.content.state.mgdl
                DebugLog.log("LA.update pushed=\(state.mgdl) heldAfter=\(String(describing: held)) boundId=\(String(describing: bound?.id.suffix(4)))")
            }
        }
    }

    @discardableResult
    func stop() -> Bool {
        let wasRunning = activity != nil
        Task {
            await activity?.end(dismissalPolicy: .immediate)
            activity = nil
        }
        return wasRunning
    }

    var isRunning: Bool { reattach() }
}
