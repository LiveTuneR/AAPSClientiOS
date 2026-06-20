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
}
