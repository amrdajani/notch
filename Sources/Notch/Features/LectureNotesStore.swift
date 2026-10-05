import AppKit
import AVFoundation
import Foundation
import Speech

/// Holds the in-flight speech request so the audio tap can append off the main thread.
private final class SpeechRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }

    func endAudio() {
        lock.lock()
        request?.endAudio()
        request = nil
        lock.unlock()
    }
}

@MainActor
@Observable
final class LectureNotesStore {
    private(set) var isRecording = false
    private(set) var isGenerating = false
    var liveTranscript = ""
    var errorMessage: String?
    var notes: [LectureNote] = []
    var search = ""
    var selectedID: UUID?
    var startedAt: Date?

    private let settings: SettingsStore
    private let schedule: ScheduleStore
    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private let requestBox = SpeechRequestBox()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var chunkTask: Task<Void, Never>?
    private var rotating = false
    private var committedTranscript = ""
    private var sessionTranscript = ""
    private let persistenceURL: URL
    private let notesFolder: URL

    init(settings: SettingsStore, schedule: ScheduleStore) {
        self.settings = settings
        self.schedule = schedule
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notch", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notch Lectures", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        persistenceURL = support.appendingPathComponent("lectures.json")
        notesFolder = documents
        load()
    }

    var selected: LectureNote? {
        notes.first { $0.id == selectedID }
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func toggle() async {
        if isRecording {
            await stopAndGenerate()
            return
        }
        await start()
    }

    func start() async {
        guard !isRecording, !isGenerating else { return }
        errorMessage = nil
        liveTranscript = ""
        committedTranscript = ""
        sessionTranscript = ""

        guard settings.isConfigured else {
            errorMessage = "Add an API key in Settings to generate notes."
            return
        }

        let speechStatus = await MediaPermissions.speech()
        guard speechStatus == .authorized else {
            errorMessage = "Allow speech recognition to transcribe the lecture."
            return
        }

        guard await MediaPermissions.microphone() else {
            errorMessage = "Allow the microphone to record the lecture."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now."
            return
        }

        do {
            try startEngine()
            beginChunk()
            startedAt = Date()
            isRecording = true
            chunkTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(45))
                    guard let self, !Task.isCancelled, self.isRecording else { return }
                    self.rotateChunk()
                }
            }
        } catch {
            teardownAudio()
            errorMessage = "Could not start the microphone."
        }
    }

    func cancel() {
        chunkTask?.cancel()
        chunkTask = nil
        teardownAudio()
        isRecording = false
        isGenerating = false
        startedAt = nil
    }

    func stopAndGenerate() async {
        guard isRecording else { return }
        chunkTask?.cancel()
        chunkTask = nil
        commitSession()
        teardownAudio()
        isGenerating = true
        isRecording = false
        let duration = elapsed
        startedAt = nil

        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.count >= 40 else {
            isGenerating = false
            errorMessage = "Not enough speech to turn into notes. Record a bit longer."
            return
        }

        await generate(from: transcript, duration: duration)
    }

    var visibleNotes: [LectureNote] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    func createNote(body: String = "") {
        errorMessage = nil
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled" : Self.title(from: trimmed, fallback: "Untitled")
        let note = LectureNote(
            id: UUID(),
            title: title,
            transcript: "",
            notes: trimmed,
            createdAt: Date(),
            duration: 0
        )
        notes.insert(note, at: 0)
        selectedID = note.id
        persist()
        writeMarkdown(note)
    }

    func closeEditor() {
        if var selected {
            let trimmed = selected.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                updateTitle(selected.id, "Untitled")
                selected.title = "Untitled"
            }
            writeMarkdown(selected)
        }
        selectedID = nil
    }

    func updateTitle(_ id: UUID, _ title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = title
        persist()
    }

    func updateBody(_ id: UUID, _ text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].notes = text
        if notes[index].title == "Untitled" {
            let derived = Self.title(from: text, fallback: "Untitled")
            if derived != "Untitled" {
                notes[index].title = derived
            }
        }
        persist()
    }

    func addTodo(from text: String) {
        schedule.addReminder(title: text)
    }

    func copyNotes() {
        guard let selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selected.notes, forType: .string)
    }

    func copyTranscript() {
        guard let selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selected.transcript, forType: .string)
    }

    func reveal(_ note: LectureNote) {
        let url = markdownURL(for: note)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? note.notes.data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func remove(_ note: LectureNote) {
        notes.removeAll { $0.id == note.id }
        if selectedID == note.id { selectedID = nil }
        persist()
        try? FileManager.default.removeItem(at: markdownURL(for: note))
    }

    private func generate(from transcript: String, duration: TimeInterval) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let clipped = String(transcript.suffix(20_000))
        do {
            let notesText = try await ChatClient.complete(
                baseURL: settings.baseURL,
                apiKey: settings.apiKey,
                model: settings.model,
                messages: [
                    .init(role: "system", content: Self.systemPrompt),
                    .init(role: "user", content: clipped)
                ]
            )
            let note = LectureNote(
                id: UUID(),
                title: Self.title(from: notesText),
                transcript: transcript,
                notes: notesText,
                createdAt: Date(),
                duration: duration
            )
            notes.insert(note, at: 0)
            selectedID = note.id
            persist()
            writeMarkdown(note)
            for item in Self.extractTodos(from: notesText) {
                schedule.addReminder(title: item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startEngine() throws {
        let box = requestBox
        try AudioCapture.start(engine) { buffer in
            box.append(buffer)
        }
    }

    private func beginChunk() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        requestBox.replace(request)

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                if let result {
                    self.sessionTranscript = result.bestTranscription.formattedString
                    self.publishTranscript()
                    if result.isFinal {
                        self.commitSession()
                    }
                }
                if error != nil, self.isRecording, !self.rotating {
                    self.rotateChunk()
                }
            }
        }
    }

    private func rotateChunk() {
        guard isRecording, !rotating else { return }
        rotating = true
        commitSession()
        requestBox.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        beginChunk()
        rotating = false
    }

    private func commitSession() {
        let piece = sessionTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty {
            if committedTranscript.isEmpty {
                committedTranscript = piece
            } else {
                committedTranscript += " " + piece
            }
        }
        sessionTranscript = ""
        publishTranscript()
    }

    private func publishTranscript() {
        let live = sessionTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if committedTranscript.isEmpty {
            liveTranscript = live
        } else if live.isEmpty {
            liveTranscript = committedTranscript
        } else {
            liveTranscript = committedTranscript + " " + live
        }
    }

    private func teardownAudio() {
        requestBox.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        AudioCapture.stop(engine)
    }

    private func markdownURL(for note: LectureNote) -> URL {
        let slug = note.title
            .replacingOccurrences(of: "/", with: "-")
            .prefix(60)
        return notesFolder.appendingPathComponent("\(slug) \(note.id.uuidString.prefix(8)).md")
    }

    private func writeMarkdown(_ note: LectureNote) {
        let text = note.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? text.data(using: .utf8)?.write(to: markdownURL(for: note))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let decoded = try? JSONDecoder().decode([LectureNote].self, from: data)
        else { return }
        notes = decoded
    }

    private static func title(from notes: String, fallback: String = "Lecture") -> String {
        let line = notes.split(whereSeparator: \.isNewline).first.map(String.init) ?? fallback
        let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(80))
    }

    private static func extractTodos(from notes: String) -> [String] {
        notes.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prefixes = ["- [ ] ", "- [ ]", "* [ ] ", "* [ ]", "☐ "]
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : text
            }
            return nil
        }
    }

    private static let systemPrompt = """
    You are a lecture note-taker. The user will paste a live transcript that may be messy.
    Produce clean Markdown notes with:
    # Title
    ## Summary
    ## Key points
    ## Terms
    ## To-dos
    - [ ] actionable follow-ups from the lecture
    ## Questions to review
    Stay faithful to the transcript. Prefer short bullets. If the audio was incomplete, note gaps instead of inventing material. Only add to-dos that are real next steps, not invented homework.
    """
}
