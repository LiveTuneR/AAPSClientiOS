import AVFoundation
import Foundation

/// Keeps the app alive in the background using a silent AVAudioEngine session.
///
/// iOS suspends network-only apps after ~3 s in background, which breaks periodic
/// Nightscout polling. Declaring the `audio` background mode and keeping an audio
/// engine running (at zero volume) prevents suspension. A Timer then drives
/// periodic store.refresh() calls while the app is backgrounded.
///
/// This is the same technique used by Loop Follow, xDrip4iOS (when no BLE),
/// and other CGM follower apps.
final class AudioKeepAlive {
    /// Foreground cadence: keep glucose, widget and Live Activity fresh while the
    /// user is looking at the app. The tick is cheap because it calls
    /// `refreshIfStale()`, which no-ops unless data is older than 60 s.
    static let foregroundInterval: TimeInterval = 60
    /// Background cadence: matches the CGM upload interval; the audio session keeps
    /// the app alive so this timer keeps firing while backgrounded.
    static let backgroundInterval: TimeInterval = 5 * 60

    private let engine = AVAudioEngine()
    private var timer: Timer?
    private var started = false

    /// BackgroundTasks-style guard: the audio keep-alive only makes sense on iOS,
    /// where the app gets suspended in the background. On Mac ("Designed for iPad")
    /// there is nothing to keep alive, so skip the audio session entirely.
    let isAudioKeepAliveEnabled: Bool

    init(isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac) {
        self.isAudioKeepAliveEnabled = !isRunningOnMac
    }

    /// App became active: fast foreground polling so the open app, widget and Live
    /// Activity update close to real time. Safe to call repeatedly.
    func enterForeground(onTick: @escaping () -> Void) {
        startEngine()
        scheduleTimer(interval: Self.foregroundInterval, onTick: onTick)
    }

    /// App went to background: drop to the 5-minute cadence; the audio session
    /// (already running from foreground) keeps the timer alive.
    func enterBackground(onTick: @escaping () -> Void) {
        startEngine()
        scheduleTimer(interval: Self.backgroundInterval, onTick: onTick)
    }

    private func startEngine() {
        guard isAudioKeepAliveEnabled, !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            engine.mainMixerNode.outputVolume = 0
            try engine.start()
        } catch {
            print("keepalive: audio session failed: \(error)")
        }
    }

    private func scheduleTimer(interval: TimeInterval, onTick: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in onTick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
