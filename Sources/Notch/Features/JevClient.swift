import AppKit
import Foundation

struct JevChoice: Sendable {
    var choice: String
    var confidence: Double
}

enum JevRoute: String, Sendable {
    case chat
    case notes
    case youtube
    case subscriptions
}

enum JevClient {
    private static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    enum ClientError: LocalizedError {
        case unauthorized
        case http(Int, String)
        case empty

        var isUnauthorized: Bool {
            if case .unauthorized = self { return true }
            return false
        }

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Jev rejected the TypeSafe API key."
            case .http(let code, let body):
                body.isEmpty ? "Jev request failed (\(code))." : body
            case .empty:
                "Jev returned no decision."
            }
        }
    }

    static func route(apiKey: String, prompt: String) async throws -> JevChoice {
        try await choose(
            apiKey: apiKey,
            state: prompt,
            instructions: "What should this Mac app do with the user's request?",
            options: [
                "chat": "Answer in the conversation. A question, explanation, or anything that does not open an app.",
                "notes": "Open Apple Notes and create a note. The user wants something written down.",
                "youtube": "Open a YouTube search in the browser for a video to watch.",
                "subscriptions": "Open the user's YouTube Subscriptions feed."
            ]
        )
    }

    static func choose(
        apiKey: String,
        state: String,
        instructions: String,
        options: [String: String]
    ) async throws -> JevChoice {
        let body = Request(
            state: state,
            model: "jev-latest",
            questions: [
                "route": Question(
                    type: "choice",
                    instructions: instructions,
                    criteria: options
                )
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw ClientError.unauthorized }
        if status >= 400 {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(status, message)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let answer = decoded.answers["route"], let choice = answer.choice, !choice.isEmpty else {
            throw ClientError.empty
        }
        return JevChoice(choice: choice, confidence: answer.confidence ?? 0)
    }

    private struct Request: Encodable {
        var state: String
        var model: String
        var questions: [String: Question]
    }

    private struct Question: Encodable {
        var type: String
        var instructions: String
        var criteria: [String: String]
    }

    private struct Response: Decodable {
        var answers: [String: Answer]
    }

    private struct Answer: Decodable {
        var choice: String?
        var confidence: Double?
    }
}

@MainActor
enum IslandActions {
    static func perform(_ route: JevRoute, prompt: String, settings: SettingsStore) async throws -> String {
        switch route {
        case .chat:
            return ""
        case .notes:
            let body = try await drafted(
                prompt: prompt,
                settings: settings,
                instruction: "Write the note the user asked for. Plain text only. No preamble."
            )
            try createNote(body)
            return "Created a note in Notes."
        case .youtube:
            let query = try await drafted(
                prompt: prompt,
                settings: settings,
                instruction: "Reply with only a short YouTube search query. No quotes."
            )
            guard let url = youtubeSearchURL(query) else { throw ActionError.badURL }
            NSWorkspace.shared.open(url)
            return "Opened YouTube search for \(query)."
        case .subscriptions:
            guard let url = URL(string: "https://www.youtube.com/feed/subscriptions") else {
                throw ActionError.badURL
            }
            NSWorkspace.shared.open(url)
            return "Opened your YouTube Subscriptions."
        }
    }

    private static func drafted(prompt: String, settings: SettingsStore, instruction: String) async throws -> String {
        guard settings.isConfigured else { return prompt }
        let text = try await ChatClient.complete(
            baseURL: settings.baseURL,
            apiKey: settings.apiKey,
            model: settings.model,
            messages: [
                .init(role: "system", content: instruction),
                .init(role: "user", content: prompt)
            ]
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func youtubeSearchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components?.url
    }

    private static func createNote(_ body: String) throws {
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Notes"
          activate
          make new note at folder "Notes" of default account with properties {body:"\(escaped)"}
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ActionError.notes(message.isEmpty ? "Couldn’t create the note." : message)
        }
    }

    private enum ActionError: LocalizedError {
        case badURL
        case notes(String)

        var errorDescription: String? {
            switch self {
            case .badURL: "Couldn’t build that link."
            case .notes(let message): message
            }
        }
    }
}
