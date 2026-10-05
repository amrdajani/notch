import AppKit
import SwiftUI

@MainActor
@Observable
final class NowPlayingStore {
    private(set) var isAvailable = false
    private(set) var isPlaying = false
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var appName = ""
    private(set) var artwork: NSImage?

    private(set) var duration: TimeInterval = 0
    private(set) var sampledElapsed: TimeInterval = 0
    private(set) var elapsedSampledAt = Date()
    private(set) var playbackRate: Double = 0
    private(set) var source: MediaSource = .remote

    private(set) var shuffleOn = false
    private(set) var repeatMode = 0
    private(set) var errorMessage: String?
    private(set) var canRequestAccess = false

    var elapsed: TimeInterval {
        guard duration > 0 else { return 0 }
        let extra = isPlaying ? Date().timeIntervalSince(elapsedSampledAt) * max(playbackRate, 0) : 0
        return min(duration, max(0, sampledElapsed + extra))
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    private var pollTask: Task<Void, Never>?
    private var lastArtworkKey = ""

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollPlayers()
                guard let self else { return }
                // Sub-second freshness only matters while something is actively
                // playing; paused/idle states don't need to spawn osascript this often.
                let delay: Duration = self.isPlaying ? .milliseconds(900)
                    : self.isAvailable ? .seconds(3)
                    : .seconds(6)
                try? await Task.sleep(for: delay)
            }
        }
    }

    func requestAccess() {
        MediaBridge.requestAutomationForRunningPlayers()
        Task { await pollPlayers() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func playPause() {
        MediaBridge.command(source, "playpause")
        isPlaying.toggle()
        elapsedSampledAt = Date()
        playbackRate = isPlaying ? 1 : 0
    }

    func next() {
        MediaBridge.command(source, "next track")
    }

    func previous() {
        MediaBridge.command(source, "previous track")
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        let target = min(duration, max(0, fraction * duration))
        MediaBridge.seek(source, to: target)
        sampledElapsed = target
        elapsedSampledAt = Date()
    }

    func toggleShuffle() {
        shuffleOn.toggle()
        switch source {
        case .music:
            MediaBridge.command(.music, "set shuffle enabled to \(shuffleOn)")
        case .spotify:
            MediaBridge.command(.spotify, "set shuffling to \(shuffleOn)")
        case .remote:
            MediaBridge.command(.remote, "toggle shuffle")
        }
    }

    func cycleRepeat() {
        repeatMode = (repeatMode + 1) % 3
        switch source {
        case .music:
            let mode = ["off", "all", "one"][repeatMode]
            MediaBridge.command(.music, "set song repeat to \(mode)")
        case .spotify:
            MediaBridge.command(.spotify, "set repeating to \(repeatMode != 0)")
        case .remote:
            MediaBridge.command(.remote, "toggle repeat")
        }
    }

    private func pollPlayers() async {
        let musicAllowed = MediaBridge.hasAutomation(.music)
        let spotifyAllowed = MediaBridge.hasAutomation(.spotify)
        async let musicTask = Task.detached {
            guard musicAllowed else { return MediaProbe() }
            return MediaBridge.probe(.music)
        }.value
        async let spotifyTask = Task.detached {
            guard spotifyAllowed else { return MediaProbe() }
            return MediaBridge.probe(.spotify)
        }.value
        async let remoteTask = Task.detached { MediaBridge.probe(.remote) }.value
        let music = await musicTask
        let spotify = await spotifyTask
        let remote = await remoteTask

        canRequestAccess =
            (!musicAllowed && MediaBridge.isRunning(.music))
            || (!spotifyAllowed && MediaBridge.isRunning(.spotify))
        if let chosen = Self.pick(music: music.snapshot, spotify: spotify.snapshot, remote: remote.snapshot) {
            errorMessage = nil
            apply(chosen)
            await refreshArtwork(for: chosen)
            return
        }
        errorMessage = remote.error ?? music.error ?? spotify.error
        if isAvailable {
            isAvailable = false
            title = ""
            artist = ""
            album = ""
            artwork = nil
            lastArtworkKey = ""
        }
    }

    private static func pick(music: MediaSnapshot?, spotify: MediaSnapshot?, remote: MediaSnapshot?) -> MediaSnapshot? {
        if let remote {
            let scriptedPlaying = (music?.isPlaying == true) || (spotify?.isPlaying == true)
            if remote.isPlaying || !scriptedPlaying {
                if remote.bundleIdentifier == MediaSource.spotify.bundleID, let spotify {
                    return spotify
                }
                if remote.bundleIdentifier == MediaSource.music.bundleID, let music {
                    return music
                }
                return remote
            }
        }
        return [music, spotify].compactMap { $0 }.first(where: \.isPlaying)
            ?? music
            ?? spotify
    }

    private func apply(_ snap: MediaSnapshot) {
        source = snap.source
        title = snap.title
        artist = snap.artist
        album = snap.album
        duration = snap.duration
        sampledElapsed = snap.elapsed
        elapsedSampledAt = Date()
        isPlaying = snap.isPlaying
        playbackRate = snap.isPlaying ? 1 : 0
        isAvailable = true
        appName = snap.appName.isEmpty ? snap.source.displayName : snap.appName
    }

    private func refreshArtwork(for snap: MediaSnapshot) async {
        let key = "\(snap.source.rawValue)|\(snap.bundleIdentifier)|\(snap.title)|\(snap.artist)"
        guard key != lastArtworkKey else { return }
        lastArtworkKey = key
        switch snap.source {
        case .music:
            let data = await MainActor.run { MediaBridge.musicArtwork() }
            if let data, let image = NSImage(data: data) {
                artwork = image
            }
        case .spotify:
            guard let url = snap.artworkURL else { return }
            let image = await Task.detached { MediaBridge.loadImage(url: url) }.value
            if let image { artwork = image }
        case .remote:
            let data = await Task.detached { MediaBridge.systemArtwork() }.value
            if let data, let image = NSImage(data: data) {
                artwork = image
            }
        }
    }
}
