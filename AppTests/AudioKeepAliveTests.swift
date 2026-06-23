import XCTest
@testable import AAPSClientiOS

final class AudioKeepAliveTests: XCTestCase {
    // AVAudioSession keep-alive exists only to dodge iOS background suspension;
    // it is pointless on Mac (Designed for iPad) and must not start an audio session there.
    func test_keepAlive_disabled_whenRunningOnMac() {
        let keepAlive = AudioKeepAlive(isRunningOnMac: true)
        XCTAssertFalse(keepAlive.isAudioKeepAliveEnabled)
    }

    func test_keepAlive_enabled_whenRunningOniOS() {
        let keepAlive = AudioKeepAlive(isRunningOnMac: false)
        XCTAssertTrue(keepAlive.isAudioKeepAliveEnabled)
    }

    // Foreground polls fast for a live UI/Live Activity; background drops to the
    // CGM upload cadence to save battery and network.
    func test_foreground_polls_faster_than_background() {
        XCTAssertLessThan(AudioKeepAlive.foregroundInterval, AudioKeepAlive.backgroundInterval)
    }

    func test_intervals_haveExpectedCadence() {
        XCTAssertEqual(AudioKeepAlive.foregroundInterval, 60)
        XCTAssertEqual(AudioKeepAlive.backgroundInterval, 5 * 60)
    }
}
