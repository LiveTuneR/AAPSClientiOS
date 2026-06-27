import AVFoundation
import Foundation
import os

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
    /// Background cadence: same 60 s. The audio session already keeps the process
    /// alive around the clock, so a slower background poll buys no battery savings —
    /// it only raises the staleness ceiling: a 5-minute poll beating against the
    /// ~5-minute CGM cadence let the Live Activity's reading age climb to ~9-11 min
    /// before the next fetch. ActivityKit applies each update() immediately (no
    /// rate budget like WidgetKit), so polling every 60 s keeps the LA within roughly
    /// one CGM interval of the latest reading.
    static let backgroundInterval: TimeInterval = 60

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var timer: Timer?
    private let log = Logger(subsystem: "com.nightaps.aapsclientios", category: "KeepAlive")

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
        guard isAudioKeepAliveEnabled, !player.isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            engine.mainMixerNode.outputVolume = 0

            if player.engine == nil {
                // `engine.attachedNodes` is NOT a reliable "have I attached player yet?"
                // check — accessing `engine.mainMixerNode` above already lazily attaches
                // the mixer/output nodes, so `attachedNodes.isEmpty` is false before we
                // ever attach `player`. That left `player` permanently unattached, and
                // calling `play()`/`scheduleBuffer` on an unattached node raises an
                // uncaught ObjC exception — an instant crash on every launch.
                engine.attach(player)
                // Engine-native format keeps the connection format-agnostic across devices.
                engine.connect(player, to: engine.mainMixerNode, format: engine.mainMixerNode.outputFormat(forBus: 0))
            }
            if !engine.isRunning { try engine.start() }

            // CoreAudio only treats the app as "playing audio" — the thing that actually
            // defers background suspension — while a node is rendering real samples.
            // A merely-started, silent-volume engine with nothing scheduled produces no
            // render activity, so iOS still suspends the process after the standard ~30 s
            // background grace period and the keep-alive timer stops ticking.
            let buffer = silentBuffer()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        } catch {
            log.error("audio keep-alive session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func silentBuffer() -> AVAudioPCMBuffer {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let frameCount = AVAudioFrameCount(format.sampleRate)  // 1 second, looped
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        return buffer
    }

    private func scheduleTimer(interval: TimeInterval, onTick: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in onTick() }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
