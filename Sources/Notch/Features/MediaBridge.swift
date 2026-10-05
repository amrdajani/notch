import AppKit
import ApplicationServices
import Foundation

enum MediaSource: String, Sendable {
    case remote
    case music
    case spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .remote: ""
        }
    }

    var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        case .remote: "Now Playing"
        }
    }
}

struct MediaSnapshot: Sendable {
    var source: MediaSource
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var artworkURL: String?
    var appName: String = ""
    var bundleIdentifier: String = ""
}

struct MediaProbe: Sendable {
    var snapshot: MediaSnapshot?
    var error: String?
}

/// Reads Music / Spotify through `/usr/bin/osascript`.
/// `NSAppleScript` on a background thread silently fails, and
/// `if application "X" is running` needs extra Automation rights.
enum MediaBridge {
    nonisolated static func isRunning(_ source: MediaSource) -> Bool {
        guard !source.bundleID.isEmpty else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == source.bundleID
        }
    }

    @discardableResult
    @MainActor
    static func requestAutomation(_ source: MediaSource) -> Bool {
        guard !source.bundleID.isEmpty else { return false }
        let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID)
        guard let desc = target.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(
            desc,
            typeWildCard,
            typeWildCard,
            true
        )
        return status == noErr
    }

    @MainActor
    static func hasAutomation(_ source: MediaSource) -> Bool {
        guard !source.bundleID.isEmpty else { return false }
        let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID)
        guard let desc = target.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(
            desc,
            typeWildCard,
            typeWildCard,
            false
        )
        return status == noErr
    }

    @MainActor
    static func requestAutomationForRunningPlayers() {
        for source: MediaSource in [.spotify, .music] where isRunning(source) {
            requestAutomation(source)
        }
    }

    nonisolated static func probe(_ source: MediaSource) -> MediaProbe {
        switch source {
        case .music: return readMusic()
        case .spotify: return readSpotify()
        case .remote: return readSystem()
        }
    }

    nonisolated static func command(_ source: MediaSource, _ verb: String) {
        switch source {
        case .music, .spotify:
            _ = run("tell application id \"\(source.bundleID)\" to \(verb)")
        case .remote:
            let id: Int
            switch verb {
            case "playpause": id = 2
            case "next track": id = 4
            case "previous track": id = 5
            case "toggle shuffle": id = 6
            case "toggle repeat": id = 7
            default: return
            }
            _ = runJS("ObjC.import('Foundation');\n\(Self.jxaLoadMediaRemote)\nObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['uint32', 'id']]);\n$.MRMediaRemoteSendCommand(\(id), null);")
        }
    }

    nonisolated static func seek(_ source: MediaSource, to seconds: TimeInterval) {
        switch source {
        case .music, .spotify:
            let value = String(format: "%.2f", seconds)
            _ = run("tell application id \"\(source.bundleID)\" to set player position to \(value)")
        case .remote:
            let value = String(format: "%.3f", seconds)
            _ = runJS("ObjC.import('Foundation');\n\(Self.jxaLoadMediaRemote)\nObjC.bindFunction('MRMediaRemoteSetElapsedTime', ['void', ['double']]);\n$.MRMediaRemoteSetElapsedTime(\(value));")
        }
    }

    @MainActor
    static func musicArtwork() -> Data? {
        var error: NSDictionary?
        let source = """
        tell application id "com.apple.Music"
          if player state is stopped then return missing value
          try
            return raw data of artwork 1 of current track
          on error
            return missing value
          end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return result.data
    }

    nonisolated static func loadImage(url: String) -> NSImage? {
        guard let remote = URL(string: url) else { return nil }
        return NSImage(contentsOf: remote)
    }

    nonisolated static func systemArtwork() -> Data? {
        switch runJS(jxaArtwork) {
        case .success(let line):
            guard !line.isEmpty else { return nil }
            return Data(base64Encoded: line, options: [.ignoreUnknownCharacters])
        case .failure:
            return nil
        }
    }

    private nonisolated static func readMusic() -> MediaProbe {
        guard isRunning(.music) else { return MediaProbe() }
        let script = """
        tell application id "com.apple.Music"
          set playerState to player state as text
          if playerState is "stopped" then return ""
          set trackName to name of current track
          set trackArtist to artist of current track
          set trackAlbum to album of current track
          set trackDuration to duration of current track
          set trackPosition to player position
          return playerState & tab & trackName & tab & trackArtist & tab & trackAlbum & tab & trackDuration & tab & trackPosition
        end tell
        """
        switch run(script) {
        case .success(let line):
            return MediaProbe(snapshot: parse(line, source: .music, durationScale: 1))
        case .failure(let message):
            return MediaProbe(error: message)
        }
    }

    private nonisolated static func readSpotify() -> MediaProbe {
        guard isRunning(.spotify) else { return MediaProbe() }
        let script = """
        tell application id "com.spotify.client"
          set playerState to player state as text
          if playerState is "stopped" then return ""
          set trackName to name of current track
          set trackArtist to artist of current track
          set trackAlbum to album of current track
          set trackDuration to duration of current track
          set trackPosition to player position
          set trackArt to artwork url of current track
          return playerState & tab & trackName & tab & trackArtist & tab & trackAlbum & tab & trackDuration & tab & trackPosition & tab & trackArt
        end tell
        """
        switch run(script) {
        case .success(let line):
            return MediaProbe(snapshot: parse(line, source: .spotify, durationScale: 0.001))
        case .failure(let message):
            return MediaProbe(error: message)
        }
    }

    private nonisolated static func parse(_ line: String, source: MediaSource, durationScale: Double) -> MediaSnapshot? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return nil }
        let title = parts[1].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return MediaSnapshot(
            source: source,
            isPlaying: parts[0] == "playing",
            title: title,
            artist: parts[2],
            album: parts[3],
            duration: (Double(parts[4]) ?? 0) * durationScale,
            elapsed: Double(parts[5]) ?? 0,
            artworkURL: parts.count > 6 ? parts[6] : nil,
            appName: source.displayName,
            bundleIdentifier: source.bundleID
        )
    }

    private nonisolated static func readSystem() -> MediaProbe {
        switch runJS(jxaNowPlaying) {
        case .success(let line):
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String,
                  !title.isEmpty
            else { return MediaProbe() }
            let bundle = json["bundle"] as? String ?? ""
            return MediaProbe(
                snapshot: MediaSnapshot(
                    source: .remote,
                    isPlaying: json["playing"] as? Bool ?? false,
                    title: title,
                    artist: json["artist"] as? String ?? "",
                    album: json["album"] as? String ?? "",
                    duration: (json["duration"] as? NSNumber)?.doubleValue ?? 0,
                    elapsed: (json["elapsed"] as? NSNumber)?.doubleValue ?? 0,
                    artworkURL: nil,
                    appName: (json["app"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Self.appName(for: bundle),
                    bundleIdentifier: bundle
                )
            )
        case .failure(let message):
            return MediaProbe(error: message)
        }
    }

    private nonisolated static func appName(for bundleID: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        switch bundleID {
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome": return "Chrome"
        case "com.brave.Browser": return "Brave"
        case "company.thebrowser.Browser": return "Arc"
        case "com.apple.Music": return "Music"
        case "com.spotify.client": return "Spotify"
        default:
            return bundleID.split(separator: ".").last.map { String($0).capitalized } ?? "Browser"
        }
    }

    private static let jxaLoadMediaRemote = """
    const __mr = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    __mr.load;
    """

    private static let jxaNowPlaying = """
    ObjC.import('Foundation');
    \(jxaLoadMediaRemote)
    function str(v) {
      if (v === undefined || v === null) return '';
      try { return String(v.js); } catch (e) { return ''; }
    }
    function num(v) {
      const n = parseFloat(str(v));
      return isFinite(n) ? n : 0;
    }
    try {
      const Request = $.NSClassFromString('MRNowPlayingRequest');
      if (!Request) { JSON.stringify({}); } else {
        const item = Request.localNowPlayingItem;
        const path = Request.localNowPlayingPlayerPath;
        const client = path && path.client;
        const info = item && item.nowPlayingInfo;
        const title = str(info && info.valueForKey('kMRMediaRemoteNowPlayingInfoTitle'));
        const rate = num(info && info.valueForKey('kMRMediaRemoteNowPlayingInfoPlaybackRate'));
        JSON.stringify({
          title: title,
          artist: str(info && info.valueForKey('kMRMediaRemoteNowPlayingInfoArtist')),
          album: str(info && info.valueForKey('kMRMediaRemoteNowPlayingInfoAlbum')),
          duration: num(info && info.valueForKey('kMRMediaRemoteNowPlayingInfoDuration')),
          elapsed: num(info && info.valueForKey('kMRMediaRemoteNowPlayingInfoElapsedTime')),
          playing: rate > 0,
          app: str(client && client.displayName),
          bundle: str(client && client.bundleIdentifier)
        });
      }
    } catch (e) {
      JSON.stringify({});
    }
    """

    private static let jxaArtwork = """
    ObjC.import('Foundation');
    \(jxaLoadMediaRemote)
    try {
      const Request = $.NSClassFromString('MRNowPlayingRequest');
      const item = Request && Request.localNowPlayingItem;
      const info = item && item.nowPlayingInfo;
      const data = info && info.valueForKey('kMRMediaRemoteNowPlayingInfoArtworkData');
      data ? ObjC.unwrap(data.base64EncodedStringWithOptions(0)) : '';
    } catch (e) { ''; }
    """

    private enum ScriptResult {
        case success(String)
        case failure(String)
    }

    private nonisolated static func runJS(_ source: String) -> ScriptResult {
        runProcess(arguments: ["-l", "JavaScript", "-"], stdin: source)
    }

    private nonisolated static func run(_ source: String) -> ScriptResult {
        runProcess(arguments: ["-"], stdin: source)
    }

    private nonisolated static func runProcess(arguments: [String], stdin source: String) -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }

        stdin.fileHandleForWriting.write(Data(source.utf8))
        try? stdin.fileHandleForWriting.close()

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        if group.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            return .failure("Music control timed out")
        }

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus == 0 {
            return .success(out)
        }

        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if err.localizedCaseInsensitiveContains("not allowed")
            || err.localizedCaseInsensitiveContains("not authorized")
            || err.localizedCaseInsensitiveContains("1002")
            || err.localizedCaseInsensitiveContains("-1743") {
            return .failure("macOS blocked Notch from controlling the player. Click Allow Access, then choose Allow.")
        }
        return .failure(err.isEmpty ? "Couldn’t read the player." : err)
    }
}
