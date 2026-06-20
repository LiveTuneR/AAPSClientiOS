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

    /// Call when the app becomes active. Safe to call repeatedly.
    func start(onTick: @escaping () -> Void) {
        startEngine()
        scheduleTimer(onTick: onTick)
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

    private func scheduleTimer(onTick: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in onTick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
