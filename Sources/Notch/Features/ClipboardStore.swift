import AppKit

struct ClipboardEntry: Identifiable {
    enum Kind: Hashable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let text: String
    let image: NSImage?
    let createdAt: Date

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return kind == .image ? "Image" : "Empty" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

@MainActor
@Observable
final class ClipboardStore {
    private(set) var items: [ClipboardEntry] = []
    private(set) var pinnedIDs: Set<UUID> = []
    private(set) var lastUserCaptureID: UUID?
    private(set) var lastCaptureAt: Date?
    var lastCopiedID: UUID?
    private(set) var lastImageID: UUID?
    /// Fired whenever a new entry lands at the top of `items`, so observers
    /// (e.g. screenshot adoption) don't need their own polling loop.
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let persistenceURL: URL
    private var maxItems = 50

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        persistenceURL = folder.appendingPathComponent("clipboard.json")
        load()
    }

    func start(maxItems: Int = 50) {
        self.maxItems = maxItems
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = entry.image {
            pasteboard.writeObjects([image])
        }
        if !entry.text.isEmpty {
            pasteboard.setString(entry.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
        lastCopiedID = entry.id
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if lastCopiedID == entry.id {
                lastCopiedID = nil
            }
        }
    }

    func remove(_ entry: ClipboardEntry) {
        items.removeAll { $0.id == entry.id }
        pinnedIDs.remove(entry.id)
        persist()
    }

    func clear() {
        // Pinned clips survive a clear.
        items.removeAll { !pinnedIDs.contains($0.id) }
        lastUserCaptureID = nil
        persist()
    }

    func isPinned(_ entry: ClipboardEntry) -> Bool {
        pinnedIDs.contains(entry.id)
    }

    func togglePin(_ entry: ClipboardEntry) {
        if pinnedIDs.contains(entry.id) {
            pinnedIDs.remove(entry.id)
        } else {
            pinnedIDs.insert(entry.id)
        }
        persist()
    }

    var pinnedItems: [ClipboardEntry] {
        items.filter { pinnedIDs.contains($0.id) }
    }

    func matches(_ entry: ClipboardEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return entry.text.localizedCaseInsensitiveContains(trimmed)
    }

    /// Trims to `maxItems`, but never drops pinned clips.
    private func enforceLimit() {
        guard items.count > maxItems else { return }
        var kept: [ClipboardEntry] = []
        var unpinnedBudget = maxItems
        for item in items {
            if pinnedIDs.contains(item.id) {
                kept.append(item)
            } else if unpinnedBudget > 0 {
                kept.append(item)
                unpinnedBudget -= 1
            }
        }
        items = kept
    }

    func ingestImage(_ image: NSImage, label: String = "Screenshot") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        lastChangeCount = pasteboard.changeCount

        let entry = ClipboardEntry(
            id: UUID(),
            kind: .image,
            text: label,
            image: image,
            createdAt: Date()
        )
        items.insert(entry, at: 0)
        enforceLimit()
        persist()
        lastCopiedID = entry.id
        lastImageID = entry.id
        onChange?()
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if lastCopiedID == entry.id {
                lastCopiedID = nil
            }
        }
    }

    func ingestCurrentPasteboard() {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        ingest(pasteboard)
    }

    func copyText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        lastChangeCount = pasteboard.changeCount

        if items.first?.text != trimmed {
            let entry = ClipboardEntry(
                id: UUID(),
                kind: .text,
                text: trimmed,
                image: nil,
                createdAt: Date()
            )
            items.insert(entry, at: 0)
            enforceLimit()
            persist()
            lastCopiedID = entry.id
        } else {
            lastCopiedID = items.first?.id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            lastCopiedID = nil
        }
    }

    var latestText: ClipboardEntry? {
        items.first { $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var wasRecentlyCaptured: Bool {
        guard let lastCaptureAt else { return false }
        return Date().timeIntervalSince(lastCaptureAt) < 8
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        ingest(pasteboard)
    }

    private func ingest(_ pasteboard: NSPasteboard) {
        let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
        let text = pasteboard.string(forType: .string) ?? ""

        guard image != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let first = items.first {
            if first.text == text, (first.image == nil) == (image == nil) {
                return
            }
        }

        let entry = ClipboardEntry(
            id: UUID(),
            kind: image != nil && text.isEmpty ? .image : .text,
            text: text,
            image: image,
            createdAt: Date()
        )
        items.insert(entry, at: 0)
        enforceLimit()
        if entry.kind == .text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastUserCaptureID = entry.id
            lastCaptureAt = entry.createdAt
        }
        if entry.kind == .image {
            lastImageID = entry.id
        }
        persist()
        onChange?()
    }

    private struct PersistedItem: Codable {
        let id: UUID
        let text: String
        let createdAt: Date
        var pinned: Bool? = false
    }

    private func persist() {
        let payload = items.map {
            PersistedItem(id: $0.id, text: $0.text, createdAt: $0.createdAt, pinned: pinnedIDs.contains($0.id))
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let decoded = try? JSONDecoder().decode([PersistedItem].self, from: data)
        else { return }
        items = decoded.map {
            ClipboardEntry(id: $0.id, kind: .text, text: $0.text, image: nil, createdAt: $0.createdAt)
        }
        pinnedIDs = Set(decoded.filter { $0.pinned == true }.map(\.id))
    }
}
