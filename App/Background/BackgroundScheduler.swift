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
    /// Runs at the start of every background wake-up, to revive the audio
    /// keep-alive if it died while the process was suspended.
    private let onWake: @MainActor () -> Void

    init(
        store: AppStore,
        scheduler: BGTaskScheduling = BGTaskScheduler.shared,
        isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac,
        onWake: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.scheduler = scheduler
        self.isRunningOnMac = isRunningOnMac
        self.onWake = onWake
    }

    func register() {
        guard !isRunningOnMac else { return }
        scheduler.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { [weak self] task in
            self?.handleRefresh(task as! BGAppRefreshTask)
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
            let ok = await performBackgroundRefresh()
            task.setTaskCompleted(success: ok)
            schedule()
        }
    }

    /// The work one background wake-up performs, split out of `handleRefresh`
    /// because `BGAppRefreshTask` has no public initializer and so cannot be
    /// constructed in tests.
    ///
    /// Reviving the keep-alive comes first: a wake-up is the only chance to
    /// restart audio that died while the process was suspended, and without it
    /// the app refreshes once and sleeps again for good.
    @discardableResult
    func performBackgroundRefresh() async -> Bool {
        await MainActor.run { onWake() }
        do {
            try await store.refresh(scope: .light)
            return true
        } catch {
            return false
        }
    }
}
