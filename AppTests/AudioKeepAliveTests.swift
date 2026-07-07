import XCTest
@testable import AAPSClientiOS

final class AudioKeepAliveTests: XCTestCase {
    func test_keepAlive_enabled_whenRunningOniOS() {
        let keepAlive = AudioKeepAlive(isRunningOnMac: false)
        XCTAssertTrue(keepAlive.isAudioKeepAliveEnabled)
    }

    func test_keepAlive_disabled_whenRunningOnMac() {
        let keepAlive = AudioKeepAlive(isRunningOnMac: true)
        XCTAssertFalse(keepAlive.isAudioKeepAliveEnabled)
    }

    func test_backgroundPollsEveryMinute() {
        XCTAssertEqual(AudioKeepAlive.backgroundInterval, 60)
        XCTAssertEqual(AudioKeepAlive.foregroundInterval, 60)
    }
}
