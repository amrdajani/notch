import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openai
    case deepseek
    case groq
    case ollama
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: "OpenAI"
        case .deepseek: "DeepSeek"
        case .groq: "Groq"
        case .ollama: "Ollama"
        case .custom: "Custom"
        }
    }

    var baseURL: String? {
        switch self {
        case .openai: "https://api.openai.com"
        case .deepseek: "https://api.deepseek.com"
        case .groq: "https://api.groq.com/openai"
        case .ollama: "http://127.0.0.1:11434"
        case .custom: nil
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: "gpt-4o-mini"
        case .deepseek: "deepseek-v4-flash"
        case .groq: "llama-3.3-70b-versatile"
        case .ollama: "llama3.2"
        case .custom: "gpt-4o-mini"
        }
    }

    var models: [String] {
        switch self {
        case .deepseek: ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .openai: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]
        default: []
        }
    }

    var needsKey: Bool { self != .ollama }

    var keyPlaceholder: String {
        switch self {
        case .deepseek: "sk-… from platform.deepseek.com"
        case .groq: "gsk-…"
        case .openai: "sk-…"
        default: "API key"
        }
    }

    var hint: String {
        switch self {
        case .deepseek:
            "DeepSeek V4. Default model is deepseek-v4-flash. Get a key at platform.deepseek.com."
        case .openai:
            "Works with OpenAI’s API."
        case .groq:
            "Groq’s OpenAI-compatible endpoint."
        case .ollama:
            "Local models. No API key needed. Run Ollama, then pick a model name you have pulled."
        case .custom:
            "Any OpenAI-compatible /v1/chat/completions endpoint."
        }
    }
}

struct SettingsChange {
    var provider: AIProvider?
    var model: String?
    var apiKey: String?
    var translateTo: String?
    var baseURL: String?
}

enum SettingsIntent {
    static func parse(_ text: String) -> SettingsChange? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let commandy = ["use ", "switch", "set ", "change", "provider", "api", "model", "translate", "key", "connect"]
        let hasCommand = commandy.contains { lower.contains($0) }
        let short = trimmed.count < 48

        var change = SettingsChange()
        var hit = false

        if lower.contains("deepseek") && (hasCommand || short) {
            change.provider = .deepseek
            if lower.contains("v4-pro") || lower.contains("deepseek pro") || lower.contains("deepseek-pro") {
                change.model = "deepseek-v4-pro"
            } else if lower.contains("v4-flash") || lower.contains("flash") {
                change.model = "deepseek-v4-flash"
            } else if lower.contains("reasoner") || lower.contains("deepseek-chat") {
                change.model = "deepseek-v4-flash"
            }
            hit = true
        } else if (lower.contains("openai") || lower.contains("gpt")) && hasCommand {
            change.provider = .openai
            hit = true
        } else if lower.contains("groq") && (hasCommand || short) {
            change.provider = .groq
            hit = true
        } else if lower.contains("ollama") && (hasCommand || short) {
            change.provider = .ollama
            hit = true
        }

        if let model = isolatedModel(from: lower) {
            change.model = model
            hit = true
        }

        if let lang = translateLanguage(from: lower) {
            change.translateTo = lang
            hit = true
        }

        if let key = apiKey(from: trimmed) {
            change.apiKey = key
            hit = true
        }

        return hit ? change : nil
    }

    private static func isolatedModel(from lower: String) -> String? {
        let models = [
            "deepseek-v4-flash", "deepseek-v4-pro",
            "gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"
        ]
        if let match = models.first(where: { lower.contains($0) }) {
            return match
        }
        if lower.contains("deepseek-reasoner") || lower.contains("deepseek-chat") {
            return "deepseek-v4-flash"
        }
        return nil
    }

    private static func translateLanguage(from lower: String) -> String? {
        guard let range = lower.range(of: "translate to ") else { return nil }
        let rest = lower[range.upperBound...]
            .split(whereSeparator: { !$0.isLetter && $0 != " " })
            .first
        guard let rest else { return nil }
        let name = String(rest).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name.capitalized
    }

    private static func apiKey(from text: String) -> String? {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard let token = parts.first(where: { $0.hasPrefix("sk-") || $0.hasPrefix("gsk-") }) else { return nil }
        let key = String(token)
        return key.count >= 12 ? key : nil
    }
}
