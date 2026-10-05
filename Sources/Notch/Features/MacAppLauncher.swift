import AppKit
import Foundation

extension Notification.Name {
    static let notchRevealApp = Notification.Name("notch.revealApp")
}

@MainActor
enum MacAppLauncher {
    /// Launches an app when the message is only asking to open one.
    /// Returns the reply to show, or nil when the message should stay in chat.
    static func openIfRequested(_ prompt: String) async -> String? {
        guard let name = appName(in: prompt) else { return nil }
        do {
            let opened = try await launch(named: name)
            NotificationCenter.default.post(name: .notchRevealApp, object: nil)
            return "Opened \(opened)."
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Couldn’t open \(name)."
        }
    }

    private static func appName(in prompt: String) -> String? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.range(of: #"\b(write|create|draft|compose|search|find a|type|click)\b"#, options: .regularExpression) != nil {
            return nil
        }
        if lower.range(of: #"\b(check|read|show|open|launch)\b"#, options: .regularExpression) != nil,
           lower.range(of: #"\b(mail|email|inbox)\b"#, options: .regularExpression) != nil {
            return "Mail"
        }
        let pattern = #"^(?:please\s+|can you\s+|could you\s+)?(?:open|launch|start|switch to|bring up|show)\s+(?:the\s+|my\s+)?(.+?)(?:\s+app)?\s*\.?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let nameRange = Range(match.range(at: 1), in: text) else { return nil }
        var name = String(text[nameRange])
        if let and = name.range(of: " and ", options: .caseInsensitive) {
            name = String(name[..<and.lowerBound])
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return name.isEmpty ? nil : name
    }

    private static func launch(named name: String) async throws -> String {
        guard let url = locate(name) else {
            throw LaunchError.missing(name)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        app.activate(options: [.activateAllWindows])
        return app.localizedName ?? url.deletingPathExtension().lastPathComponent
    }

    private static func locate(_ name: String) -> URL? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let bundleID = bundles[key],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        let folders = [
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        let wanted = key.hasSuffix(".app") ? key : key + ".app"
        for folder in folders {
            if let found = findApp(named: wanted, in: URL(fileURLWithPath: folder)) {
                return found
            }
        }
        return nil
    }

    private static func findApp(named wanted: String, in folder: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            let filename = entry.lastPathComponent.lowercased()
            if filename == wanted { return entry }
            if filename.hasSuffix(".app") { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if let nested = findApp(named: wanted, in: entry) { return nested }
        }
        return nil
    }

    private static let bundles: [String: String] = [
        "mail": "com.apple.mail",
        "email": "com.apple.mail",
        "inbox": "com.apple.mail",
        "notes": "com.apple.Notes",
        "safari": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "arc": "company.thebrowser.Browser",
        "spotify": "com.spotify.client",
        "calendar": "com.apple.iCal",
        "messages": "com.apple.MobileSMS",
        "finder": "com.apple.finder",
        "music": "com.apple.Music",
        "photos": "com.apple.Photos",
        "terminal": "com.apple.Terminal",
        "system settings": "com.apple.systempreferences",
        "settings": "com.apple.systempreferences",
        "reminders": "com.apple.reminders",
        "maps": "com.apple.Maps",
        "preview": "com.apple.Preview"
    ]

    private enum LaunchError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name): "Couldn’t find an app named \(name)."
            }
        }
    }
}
