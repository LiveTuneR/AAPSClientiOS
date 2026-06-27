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

    // Background polls at the same 60 s cadence as foreground: the audio session keeps
    // the process alive regardless, so a slower background interval only raises the Live
    // Activity's staleness ceiling (a 5-min poll beating the ~5-min CGM cadence pushed
    // reading age to ~9-11 min). ActivityKit has no per-update rate budget, so 60 s keeps
    // the LA within roughly one CGM interval of the latest reading.
    func test_background_polls_as_fast_as_foreground() {
        XCTAssertEqual(AudioKeepAlive.foregroundInterval, AudioKeepAlive.backgroundInterval)
    }

    func test_intervals_haveExpectedCadence() {
        XCTAssertEqual(AudioKeepAlive.foregroundInterval, 60)
        XCTAssertEqual(AudioKeepAlive.backgroundInterval, 60)
    }
}
