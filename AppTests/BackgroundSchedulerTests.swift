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
    @MainActor
    private func makeStore() -> AppStore {
        AppStore(client: FixtureNightscoutClient(), alarmEngine: AlarmEngineLive())
    }

    // BGTaskScheduler is unsupported for "Designed for iPad" apps running on Mac;
    // calling register()/submit() there throws an uncaught NSException at launch.
    @MainActor
    func test_register_skipsBGTaskScheduler_whenRunningOnMac() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: true)

        scheduler.register()

        XCTAssertTrue(spy.registeredIdentifiers.isEmpty)
    }

    @MainActor
    func test_schedule_skipsBGTaskScheduler_whenRunningOnMac() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: true)

        scheduler.schedule()

        XCTAssertTrue(spy.submittedRequests.isEmpty)
    }

    @MainActor
    func test_register_registersRefreshTask_whenRunningOniOS() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: false)

        scheduler.register()

        XCTAssertEqual(spy.registeredIdentifiers, [BackgroundScheduler.refreshTaskId])
    }

    @MainActor
    func test_schedule_submitsRefreshRequest_whenRunningOniOS() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: false)

        scheduler.schedule()

        XCTAssertEqual(spy.submittedRequests.map(\.identifier), [BackgroundScheduler.refreshTaskId])
    }

    @MainActor
    func test_schedule_isIdempotentAndResubmits() {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: false)

        scheduler.schedule()
        scheduler.schedule()

        XCTAssertEqual(spy.submittedRequests.count, 2)
        XCTAssertEqual(
            Set(spy.submittedRequests.map(\.identifier)),
            [BackgroundScheduler.refreshTaskId]
        )
    }

    // A BGAppRefresh wake-up is the only thing that can reach the app after the
    // audio keep-alive died and the process was suspended. If it refreshes data
    // but leaves the keep-alive dead, the app just goes back to sleep and stays
    // dead until the user opens it by hand.
    @MainActor
    func test_backgroundRefresh_revivesTheKeepAlive() async {
        var revived = false
        let scheduler = BackgroundScheduler(
            store: makeStore(),
            scheduler: SpyTaskScheduler(),
            isRunningOnMac: false,
            onWake: { revived = true }
        )

        _ = await scheduler.performBackgroundRefresh()

        XCTAssertTrue(revived)
    }

    @MainActor
    func test_backgroundRefresh_reportsSuccess_whenRefreshSucceeds() async {
        let scheduler = BackgroundScheduler(
            store: makeStore(),
            scheduler: SpyTaskScheduler(),
            isRunningOnMac: false
        )

        let ok = await scheduler.performBackgroundRefresh()

        XCTAssertTrue(ok)
    }

    @MainActor
    func test_backgroundRefresh_reportsFailure_whenRefreshThrows() async {
        let client = FixtureNightscoutClient()
        client.shouldThrow = NsError.noNetwork
        let store = AppStore(client: client, alarmEngine: AlarmEngineLive())
        let scheduler = BackgroundScheduler(
            store: store,
            scheduler: SpyTaskScheduler(),
            isRunningOnMac: false
        )

        let ok = await scheduler.performBackgroundRefresh()

        XCTAssertFalse(ok)
    }

    @MainActor
    func test_scheduledRequestIsNotEarlierThanFiveMinutes() throws {
        let spy = SpyTaskScheduler()
        let scheduler = BackgroundScheduler(store: makeStore(), scheduler: spy, isRunningOnMac: false)

        scheduler.schedule()

        let request = try XCTUnwrap(spy.submittedRequests.first as? BGAppRefreshTaskRequest)
        let earliest = try XCTUnwrap(request.earliestBeginDate)
        XCTAssertGreaterThan(earliest.timeIntervalSinceNow, 4 * 60)
    }
}
