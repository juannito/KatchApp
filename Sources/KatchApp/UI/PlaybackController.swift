import AVFoundation
import Foundation
import SwiftUI

/// Plays a session's audio.wav and publishes the playhead for transcript highlighting.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var available = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        unload()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        available = true
        Task { [weak self] in
            let d = (try? await item.asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            await MainActor.run { self?.duration = d.isFinite ? d : 0 }
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                let s = CMTimeGetSeconds(t)
                if s.isFinite { self.currentTime = s }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
                self?.currentTime = 0
            }
        }
    }

    func unload() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        available = false
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to seconds: Double, andPlay: Bool = false) {
        guard let player else { return }
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 1000)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        if andPlay, !isPlaying {
            player.play()
            isPlaying = true
        }
    }

    func skip(_ delta: Double) {
        seek(to: min(max(0, currentTime + delta), duration))
    }
}

/// Transport bar: play/pause, ±10 s, scrubber and time.
struct PlaybackBar: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 12) {
            Button { playback.skip(-10) } label: { Image(systemName: "gobackward.10") }
                .buttonStyle(.borderless)
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .help(playback.isPlaying ? L("Pause") : L("Play"))
            Button { playback.skip(10) } label: { Image(systemName: "goforward.10") }
                .buttonStyle(.borderless)
            Text(TimeFormat.clock(playback.currentTime))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
            Slider(
                value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                in: 0...max(playback.duration, 0.001))
            Text(TimeFormat.clock(playback.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .disabled(!playback.available)
    }
}
