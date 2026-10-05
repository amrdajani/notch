import Foundation

@MainActor
@Observable
final class ClipboardAIStore {
    var runningAction: ClipboardAction?
    var result: String?
    var resultAction: ClipboardAction?
    var sourceID: UUID?
    var errorMessage: String?
    var copiedResult = false

    private let settings: SettingsStore
    private var streamTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isRunning: Bool { runningAction != nil }

    func prepareForCapture(_ entry: ClipboardEntry?) {
        guard let entry, entry.kind == .text, !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if entry.text == result { return }
        sourceID = entry.id
        result = nil
        resultAction = nil
        errorMessage = nil
        copiedResult = false
    }

    func run(_ action: ClipboardAction, on entry: ClipboardEntry) {
        let text = String(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12_000))
        guard !text.isEmpty else { return }
        guard settings.isConfigured else {
            errorMessage = "Add an API key in Settings."
            return
        }

        streamTask?.cancel()
        runningAction = action
        errorMessage = nil
        copiedResult = false
        sourceID = entry.id
        result = nil
        resultAction = action

        streamTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.runningAction = nil
                self.streamTask = nil
            }
            do {
                try await ChatClient.stream(
                    baseURL: self.settings.baseURL,
                    apiKey: self.settings.apiKey,
                    model: self.settings.model,
                    messages: [
                        .init(role: "system", content: action.systemPrompt(translateTo: self.settings.translateTo)),
                        .init(role: "user", content: text)
                    ]
                ) { token in
                    self.result = (self.result ?? "") + token
                }
                if self.result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    self.result = nil
                    self.resultAction = nil
                    self.errorMessage = ChatClient.ClientError.empty.localizedDescription
                }
            } catch is CancellationError {
                if self.result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    self.result = nil
                    self.resultAction = nil
                }
            } catch {
                if !Task.isCancelled {
                    if self.result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                        self.result = nil
                        self.resultAction = nil
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        runningAction = nil
        if result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            result = nil
            resultAction = nil
        }
    }

    func markResultCopied() {
        copiedResult = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            copiedResult = false
        }
    }
}
