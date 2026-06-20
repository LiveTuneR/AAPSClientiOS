import BackgroundTasks
import Foundation

/// System BGTaskScheduler seam so the scheduler can be tested without the real
/// singleton (which is also unavailable for iOS apps running on Mac).
protocol BGTaskScheduling {
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool
    func submit(_ taskRequest: BGTaskRequest) throws
}

extension BGTaskScheduler: BGTaskScheduling {}

final class BackgroundScheduler {
    static let refreshTaskId = "com.nightaps.aapsclientios.refresh"

    private let store: AppStore
    private let scheduler: BGTaskScheduling
    /// BackgroundTasks is unsupported for "Designed for iPad" apps running on Mac;
    /// touching BGTaskScheduler there throws an uncaught NSException and crashes
    /// the app at launch. Skip all BG work in that environment.
    private let isRunningOnMac: Bool

    init(
        store: AppStore,
        scheduler: BGTaskScheduling = BGTaskScheduler.shared,
        isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac
    ) {
        self.store = store
        self.scheduler = scheduler
        self.isRunningOnMac = isRunningOnMac
    }

    func register() {
        guard !isRunningOnMac else { return }
        scheduler.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
            self.handleRefresh(task as! BGAppRefreshTask)
        }
    }

    func schedule() {
        guard !isRunningOnMac else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        do {
            try scheduler.submit(request)
        } catch {
            print("bg: failed to schedule refresh: \(error)")
        }
    }

    private func handleRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        Task {
            do {
                try await store.refresh()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
            schedule()
        }
    }
}
