import Foundation
import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class ChatStore {
    var messages: [ChatMessage] = []
    var draft = ""
    var isSending = false
    var errorMessage: String?

    private let settings: SettingsStore
    private var streamTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        draft = ""
        errorMessage = nil
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            messages.append(ChatMessage(role: .user, text: displayPrompt(prompt)))
        }

        if let change = SettingsIntent.parse(prompt) {
            let summary = settings.apply(change)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84).delay(0.08)) {
                messages.append(ChatMessage(role: .assistant, text: summary))
            }
            return
        }

        if let reply = await MacAppLauncher.openIfRequested(prompt) {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                messages.append(ChatMessage(role: .assistant, text: reply))
            }
            return
        }

        if settings.hasJevKey, await routeWithJev(prompt) {
            return
        }

        guard settings.isConfigured else {
            errorMessage = settings.provider == .deepseek
                ? "Add your DeepSeek API key in Settings, or paste it here."
                : "Add an API key in Settings."
            return
        }

        isSending = true
        let history = apiMessages()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84).delay(0.06)) {
            messages.append(ChatMessage(role: .assistant, text: ""))
        }
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSending = false
                self.streamTask = nil
            }
            do {
                try await ChatClient.stream(
                    baseURL: self.settings.baseURL,
                    apiKey: self.settings.apiKey,
                    model: self.settings.model,
                    messages: history
                ) { token in
                    self.appendStream(token)
                }
                if self.messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    self.removeEmptyAssistant()
                    self.errorMessage = ChatClient.ClientError.empty.localizedDescription
                }
            } catch is CancellationError {
                self.removeEmptyAssistant()
            } catch {
                if !Task.isCancelled {
                    self.removeEmptyAssistant()
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isSending = false
        removeEmptyAssistant()
    }

    func clear() {
        stop()
        withAnimation(.easeOut(duration: 0.2)) {
            messages.removeAll()
        }
        errorMessage = nil
    }

    private func routeWithJev(_ prompt: String) async -> Bool {
        do {
            let decision = try await JevClient.route(apiKey: settings.jevAPIKey, prompt: prompt)
            guard decision.confidence >= 0.55,
                  let route = JevRoute(rawValue: decision.choice),
                  route != .chat
            else { return false }
            let reply: String
            do {
                reply = try await IslandActions.perform(route, prompt: prompt, settings: settings)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return true
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                messages.append(ChatMessage(role: .assistant, text: reply))
            }
            return true
        } catch let error as JevClient.ClientError where error.isUnauthorized {
            errorMessage = error.localizedDescription
            return true
        } catch {
            return false
        }
    }

    private func appendStream(_ token: String) {
        guard let index = messages.indices.last, messages[index].role == .assistant else { return }
        messages[index].text += token
    }

    private func removeEmptyAssistant() {
        guard let last = messages.last, last.role == .assistant,
              last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.removeLast()
    }

    private func displayPrompt(_ prompt: String) -> String {
        if SettingsIntent.parse(prompt) != nil, prompt.split(whereSeparator: \.isWhitespace).contains(where: { $0.hasPrefix("sk-") || $0.hasPrefix("gsk-") }) {
            return "Update API key"
        }
        return prompt
    }

    private func apiMessages() -> [ChatClient.Message] {
        var payload: [ChatClient.Message] = [
            .init(
                role: "system",
                content: """
                You live in a compact MacBook notch tray. Be useful, brief, and concrete.
                Current provider: \(settings.provider.title). Model: \(settings.model).
                Prefer short paragraphs or tight bullets.
                Notch itself opens apps when the user asks. A previous message that says "Opened …" is true. Never retract it, and never say you cannot open apps.
                """
            )
        ]
        payload += messages.suffix(16).map {
            .init(role: $0.role.rawValue, content: $0.text)
        }
        return payload
    }
}

enum ChatClient {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Request: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]?
        let error: APIError?
    }

    struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        let choices: [Choice]?
        let error: APIError?
    }

    struct APIError: Decodable {
        let message: String?
    }

    enum ClientError: LocalizedError {
        case badURL
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .badURL:
                "The API base URL is invalid."
            case .http(let code, let body):
                body.isEmpty ? "Request failed (\(code))." : body
            case .empty:
                "The model returned an empty reply."
            }
        }
    }

    static func complete(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [Message]
    ) async throws -> String {
        guard let url = completionsURL(from: baseURL) else { throw ClientError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, messages: messages, temperature: 0.4, stream: false)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(Response.self, from: data)

        if status >= 400 {
            let message = decoded?.error?.message ?? String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(status, message)
        }

        let text = decoded?.choices?.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { throw ClientError.empty }
        return text
    }

    static func stream(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [Message],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        guard let url = completionsURL(from: baseURL) else { throw ClientError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, messages: messages, temperature: 0.4, stream: true)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let decoded = try? JSONDecoder().decode(Response.self, from: data)
            let message = decoded?.error?.message ?? String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(status, message)
        }

        var sawToken = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload: String
            if trimmed.hasPrefix("data:") {
                payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("{") {
                payload = trimmed
            } else {
                continue
            }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            if let error = try? JSONDecoder().decode(Response.self, from: data), let message = error.error?.message {
                throw ClientError.http(status, message)
            }
            guard
                let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                let token = chunk.choices?.first?.delta?.content,
                !token.isEmpty
            else { continue }
            sawToken = true
            await onToken(token)
        }

        if !sawToken { throw ClientError.empty }
    }

    private static func completionsURL(from base: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        if trimmed.hasSuffix("/v1") {
            return URL(string: trimmed + "/chat/completions")
        }
        return URL(string: trimmed + "/v1/chat/completions")
    }
}
