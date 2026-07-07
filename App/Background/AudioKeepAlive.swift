import AVFoundation
import Foundation
import os

/// Keeps local Nightscout polling alive in the background by rendering silence.
final class AudioKeepAlive {
    static let foregroundInterval: TimeInterval = 60
    static let backgroundInterval: TimeInterval = 60

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var timer: Timer?
    private let log = Logger(subsystem: "com.nightaps.aapsclientios", category: "KeepAlive")

    let isAudioKeepAliveEnabled: Bool

    init(isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac) {
        self.isAudioKeepAliveEnabled = !isRunningOnMac
    }

    func enterForeground(onTick: @escaping () -> Void) {
        startEngine()
        scheduleTimer(interval: Self.foregroundInterval, onTick: onTick)
    }

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
                engine.attach(player)
                engine.connect(
                    player,
                    to: engine.mainMixerNode,
                    format: engine.mainMixerNode.outputFormat(forBus: 0)
                )
            }
            if !engine.isRunning { try engine.start() }

            guard let buffer = silentBuffer() else {
                log.error("audio keep-alive could not allocate a silent buffer")
                return
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        } catch {
            log.error("audio keep-alive session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func silentBuffer() -> AVAudioPCMBuffer? {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        return buffer
    }

    private func scheduleTimer(interval: TimeInterval, onTick: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            onTick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
