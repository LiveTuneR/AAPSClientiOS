import AVFoundation
import Foundation
import os

/// Seam over the real audio player so interruption recovery can be tested
/// without audio hardware.
protocol KeepAlivePlayer: AnyObject {
    var isActuallyPlaying: Bool { get }
    func start()
    func stop()
    func reset()
}

/// Plays generated silence on an endless loop to keep the process scheduled in
/// the background.
final class SilentLoopPlayer: KeepAlivePlayer {
    private var player: AVAudioPlayer?
    private let log = Logger(subsystem: "com.nightaps.aapsclientios", category: "KeepAlive")

    var isActuallyPlaying: Bool { player?.isPlaying ?? false }

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if player == nil {
                player = try makePlayer()
            }
            player?.numberOfLoops = -1
            player?.volume = 0.01
            player?.prepareToPlay()
            player?.play()
        } catch {
            log.error("keep-alive start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func reset() {
        player?.stop()
        player = nil
        start()
    }

    private func makePlayer() throws -> AVAudioPlayer {
        let url = try Self.silenceFileURL()
        return try AVAudioPlayer(contentsOf: url)
    }

    private static func silenceFileURL() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keepalive-silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate = 44100
        let sampleCount = sampleRate
        let dataBytes = sampleCount * 2

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataBytes).littleEndian, Array.init))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian, Array.init))
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(dataBytes).littleEndian, Array.init))
        wav.append(contentsOf: [UInt8](repeating: 0, count: dataBytes))

        try wav.write(to: url)
        return url
    }
}
