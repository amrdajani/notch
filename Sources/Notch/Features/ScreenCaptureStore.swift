import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureMode {
    case display
    case selection
    case window
}

struct CaptureShot: Identifiable {
    let id: UUID
    let image: NSImage
    let fileURL: URL?
    let createdAt: Date
}

@MainActor
@Observable
final class ScreenCaptureStore {
    var isCapturing = false
    var lastImage: NSImage?
    var lastFileURL: URL?
    var errorMessage: String?
    var recent: [CaptureShot] = []
    var importGeneration = 0

    var hideIsland: (() async -> Void)?
    var showIsland: (() -> Void)?

    private let clipboard: ClipboardStore
    private let savesFolder: URL
    private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var scanDebounce: Task<Void, Never>?
    private var seenPaths: Set<String> = []
    private var lastAdoptedClipboardID: UUID?
    private var watchFolders: [URL] = []

    init(clipboard: ClipboardStore) {
        self.clipboard = clipboard
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        savesFolder = pictures.appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: savesFolder, withIntermediateDirectories: true)
    }

    func startWatching() {
        watchFolders = Self.screenshotFolders()
        seenPaths = Set(watchFolders.flatMap { Self.imagePaths(in: $0) })
        seenPaths.formUnion(Self.imagePaths(in: savesFolder))
        lastAdoptedClipboardID = clipboard.lastImageID

        stopFileWatchers()
        for folder in watchFolders + [savesFolder] {
            guard let source = Self.makeWatcher(for: folder, handler: { [weak self] in
                self?.scheduleScan()
            }) else { continue }
            fileWatchers.append(source)
        }

        // Adopting an already-copied screenshot only touches in-memory state,
        // so it can piggyback on the clipboard store's own change notifications
        // instead of running its own I/O-driving poll loop.
        clipboard.onChange = { [weak self] in self?.adoptClipboardImageIfNeeded() }
    }

    func stopWatching() {
        stopFileWatchers()
        scanDebounce?.cancel()
        scanDebounce = nil
        if clipboard.onChange != nil { clipboard.onChange = nil }
    }

    private func stopFileWatchers() {
        for source in fileWatchers { source.cancel() }
        fileWatchers.removeAll()
    }

    private static func makeWatcher(for folder: URL, handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.main
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// New screenshot files can still be mid-write when the fs event fires,
    /// so coalesce bursts and let `waitUntilStable` confirm the file settled.
    private func scheduleScan() {
        scanDebounce?.cancel()
        scanDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.scanForSystemScreenshots()
        }
    }

    func capture(_ mode: CaptureMode) async {
        guard !isCapturing else { return }
        isCapturing = true
        errorMessage = nil
        defer {
            isCapturing = false
            showIsland?()
        }

        await hideIsland?()

        switch mode {
        case .display:
            await captureDisplay()
        case .selection:
            await captureInteractive(windowMode: false)
        case .window:
            await captureInteractive(windowMode: true)
        }
    }

    func revealLast() {
        guard let lastFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastFileURL])
    }

    func copyLast() {
        guard let lastImage else { return }
        clipboard.ingestImage(lastImage, label: "Screenshot")
        lastAdoptedClipboardID = clipboard.lastImageID
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func captureDisplay() async {
        guard requestAccess() else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let targetID = NotchGeometry.preferredScreen().displayID
            guard let display = content.displays.first(where: { $0.displayID == targetID }) ?? content.displays.first else {
                errorMessage = "No display available to capture."
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            finish(with: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func captureInteractive(windowMode: Bool) async {
        var arguments = ["-x", "-c", "-i"]
        if windowMode {
            arguments.append("-W")
        }
        let ok = await runScreencapture(arguments)
        guard ok else {
            // User cancelled the crosshair, or permission was denied.
            if !CGPreflightScreenCaptureAccess() {
                errorMessage = "Allow Screen Recording in System Settings to capture."
            }
            return
        }
        clipboard.ingestCurrentPasteboard()
        if let image = clipboard.items.first(where: { $0.kind == .image })?.image {
            lastAdoptedClipboardID = clipboard.lastImageID
            record(image, fileURL: save(image), announce: false)
        }
    }

    private func finish(with image: NSImage) {
        let url = save(image)
        clipboard.ingestImage(image, label: "Screenshot")
        lastAdoptedClipboardID = clipboard.lastImageID
        record(image, fileURL: url, announce: false)
    }

    private func save(_ image: NSImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let name = "Notch \(formatter.string(from: Date())).png"
        let url = savesFolder.appendingPathComponent(name)
        seenPaths.insert(url.path)
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func scanForSystemScreenshots() {
        let paths = watchFolders.flatMap { Self.imagePaths(in: $0) }
        for path in paths where !seenPaths.contains(path) {
            seenPaths.insert(path)
            let url = URL(fileURLWithPath: path)
            guard Self.shouldImport(url) else { continue }
            Task { await adoptScreenshotFile(url) }
        }
    }

    private func adoptScreenshotFile(_ url: URL) async {
        let ready = await Self.waitUntilStable(url)
        guard ready, let image = NSImage(contentsOf: url) else { return }
        clipboard.ingestImage(image, label: "Screenshot")
        lastAdoptedClipboardID = clipboard.lastImageID
        record(image, fileURL: url, announce: true)
    }

    private func adoptClipboardImageIfNeeded() {
        guard !isCapturing else { return }
        guard let item = clipboard.items.first, item.kind == .image, let image = item.image else { return }
        guard item.id != lastAdoptedClipboardID else { return }
        lastAdoptedClipboardID = item.id
        record(image, fileURL: nil, announce: true)
    }

    private func record(_ image: NSImage, fileURL: URL?, announce: Bool) {
        lastImage = image
        lastFileURL = fileURL
        let shot = CaptureShot(id: UUID(), image: image, fileURL: fileURL, createdAt: Date())
        recent.insert(shot, at: 0)
        if recent.count > 12 {
            recent = Array(recent.prefix(12))
        }
        if announce {
            importGeneration += 1
        }
    }

    private static func screenshotFolders() -> [URL] {
        var folders: [URL] = []
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
            folders.append(url)
        }
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            folders.append(desktop)
        }
        var unique: [URL] = []
        var seen = Set<String>()
        for folder in folders {
            let path = folder.standardizedFileURL.path
            if seen.insert(path).inserted {
                unique.append(folder)
            }
        }
        return unique
    }

    private static func imagePaths(in folder: URL) -> [String] {
        let allowed: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.compactMap { url in
            guard allowed.contains(url.pathExtension.lowercased()) else { return nil }
            return url.standardizedFileURL.path
        }
    }

    private static func shouldImport(_ url: URL) -> Bool {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?
            .standardizedFileURL.path, folder == desktop {
            return isLikelyScreenshotName(url)
        }
        return true
    }

    private static func isLikelyScreenshotName(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let markers = [
            "screenshot", "screen shot", "screen recording",
            "bildschirmfoto", "capture d", "captura", "schermata"
        ]
        return markers.contains { name.contains($0) }
    }

    private static func waitUntilStable(_ url: URL) async -> Bool {
        func size() -> Int {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }
        try? await Task.sleep(for: .milliseconds(250))
        let first = size()
        try? await Task.sleep(for: .milliseconds(200))
        let second = size()
        return first > 0 && first == second
    }

    private func requestAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        if CGPreflightScreenCaptureAccess() { return true }
        errorMessage = "Allow Screen Recording in System Settings to capture."
        return false
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("declin") || text.localizedCaseInsensitiveContains("not author") {
            return "Allow Screen Recording in System Settings to capture."
        }
        return text
    }

    private func runScreencapture(_ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
