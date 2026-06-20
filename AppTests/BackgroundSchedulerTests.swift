import XCTest
import BackgroundTasks
@testable import AAPSClientiOS

/// Records calls instead of touching the real system BGTaskScheduler.
final class SpyTaskScheduler: BGTaskScheduling {
    var registeredIdentifiers: [String] = []
    var submittedRequests: [BGTaskRequest] = []

    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        return true
    }

    func submit(_ taskRequest: BGTaskRequest) throws {
        submittedRequests.append(taskRequest)
    }
}

final class BackgroundSchedulerTests: XCTestCase {
    private func makeStore() -> AppStore {
        AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
    }

    // BGTaskScheduler is unsupported for "Designed for iPad" apps running on Mac;
    // calling register()/submit() there throws an uncaught NSException at launch.
    func test_register_skipsBGTaskScheduler_whenRunningOnMac() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: true)

        scheduler.register()

        XCTAssertTrue(spy.registeredIdentifiers.isEmpty)
    }

    func test_schedule_skipsBGTaskScheduler_whenRunningOnMac() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: true)

        scheduler.schedule()

        XCTAssertTrue(spy.submittedRequests.isEmpty)
    }

    func test_register_registersRefreshTask_whenRunningOniOS() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: false)

        scheduler.register()

        XCTAssertEqual(spy.registeredIdentifiers, [BackgroundScheduler.refreshTaskId])
    }

    func test_schedule_submitsRefreshRequest_whenRunningOniOS() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: false)

        scheduler.schedule()

        XCTAssertEqual(spy.submittedRequests.map(\.identifier), [BackgroundScheduler.refreshTaskId])
    }
}
