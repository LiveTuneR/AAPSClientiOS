import AVFoundation
import XCTest
@testable import AAPSClientiOS

final class SpyKeepAlivePlayer: KeepAlivePlayer {
    var startCount = 0
    var stopCount = 0
    var resetCount = 0
    var isActuallyPlaying = false

    func start() {
        startCount += 1
        isActuallyPlaying = true
    }

    func stop() {
        stopCount += 1
        isActuallyPlaying = false
    }

    func reset() {
        resetCount += 1
        isActuallyPlaying = true
    }
}

final class AudioKeepAliveTests: XCTestCase {
    private var player: SpyKeepAlivePlayer!
    private var center: NotificationCenter!
    private var keepAlive: AudioKeepAlive!

    override func setUp() {
        super.setUp()
        player = SpyKeepAlivePlayer()
        center = NotificationCenter()
        keepAlive = AudioKeepAlive(
            player: player,
            notificationCenter: center,
            isRunningOnMac: false
        )
    }

    func test_keepAlive_enabled_whenRunningOniOS() {
        XCTAssertTrue(keepAlive.isAudioKeepAliveEnabled)
    }

    func test_keepAlive_disabled_whenRunningOnMac() {
        let macKeepAlive = AudioKeepAlive(
            player: SpyKeepAlivePlayer(),
            notificationCenter: NotificationCenter(),
            isRunningOnMac: true
        )
        XCTAssertFalse(macKeepAlive.isAudioKeepAliveEnabled)
    }

    func test_entersBackground_startsPlayback_inNormalMode() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})

        XCTAssertEqual(player.startCount, 1)
    }

    func test_entersBackground_doesNotStartPlayback_inDisabledMode() {
        keepAlive.enterBackground(mode: .disabled, nextDelay: { 60 }, onTick: {})

        XCTAssertEqual(player.startCount, 0)
    }

    func test_entersBackground_doesNotStartPlayback_onMac() {
        let macPlayer = SpyKeepAlivePlayer()
        let macKeepAlive = AudioKeepAlive(
            player: macPlayer,
            notificationCenter: NotificationCenter(),
            isRunningOnMac: true
        )

        macKeepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})

        XCTAssertEqual(macPlayer.startCount, 0)
    }

    func test_entersForeground_stopsPlayback() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})

        keepAlive.enterForeground(onTick: {})

        XCTAssertEqual(player.stopCount, 1)
    }

    func test_restartsPlayback_whenInterruptionEnds() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})
        player.isActuallyPlaying = false
        let startsBefore = player.startCount

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
            ]
        )

        XCTAssertEqual(player.startCount, startsBefore + 1)
    }

    func test_doesNotRestartPlayback_whenInterruptionBegins() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})
        let startsBefore = player.startCount

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )

        XCTAssertEqual(player.startCount, startsBefore)
    }

    func test_rebuildsPlayer_whenMediaServicesReset() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)

        XCTAssertEqual(player.resetCount, 1)
    }

    func test_restartsPlayback_onRouteChange_whenPlaybackStopped() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})
        player.isActuallyPlaying = false
        let startsBefore = player.startCount

        center.post(name: AVAudioSession.routeChangeNotification, object: nil)

        XCTAssertEqual(player.startCount, startsBefore + 1)
    }

    func test_ignoresAudioNotifications_whenInForeground() {
        keepAlive.enterForeground(onTick: {})
        player.isActuallyPlaying = false
        let startsBefore = player.startCount

        center.post(name: AVAudioSession.routeChangeNotification, object: nil)

        XCTAssertEqual(player.startCount, startsBefore)
    }

    func test_watchdogRestartsPlayback_whenPlaybackDiedSilently() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})
        player.isActuallyPlaying = false
        let startsBefore = player.startCount

        keepAlive.ensurePlaying()

        XCTAssertEqual(player.startCount, startsBefore + 1)
    }

    func test_watchdogDoesNothing_whenPlaybackIsHealthy() {
        keepAlive.enterBackground(mode: .normal, nextDelay: { 60 }, onTick: {})
        let startsBefore = player.startCount

        keepAlive.ensurePlaying()

        XCTAssertEqual(player.startCount, startsBefore)
    }
}
