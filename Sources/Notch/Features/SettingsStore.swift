import Foundation

@MainActor
@Observable
final class SettingsStore {
    var provider: AIProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider)
            guard !isLoading, oldValue != provider else { return }
            if let url = provider.baseURL {
                baseURL = url
            }
            if provider != .custom {
                model = provider.defaultModel
            }
            apiKey = KeychainStore.get(account: Keys.account(for: provider)) ?? ""
        }
    }

    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    var apiKey: String {
        didSet {
            guard !isLoading else { return }
            KeychainStore.set(apiKey, account: Keys.account(for: provider))
        }
    }

    var maxClipboardItems: Int {
        didSet { UserDefaults.standard.set(maxClipboardItems, forKey: Keys.maxClipboard) }
    }

    var translateTo: String {
        didSet { UserDefaults.standard.set(translateTo, forKey: Keys.translateTo) }
    }

    var notchWidth: Double {
        didSet { UserDefaults.standard.set(notchWidth, forKey: Keys.notchWidth) }
    }

    var jevAPIKey: String {
        didSet {
            guard !isLoading else { return }
            KeychainStore.set(jevAPIKey, account: Keys.jev)
        }
    }

    var hasJevKey: Bool {
        !jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConfigured: Bool {
        if !provider.needsKey { return true }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLoading = true

    init() {
        let defaults = UserDefaults.standard
        let storedURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com"
        let storedProvider = defaults.string(forKey: Keys.provider).flatMap(AIProvider.init(rawValue:))
        let resolvedProvider: AIProvider
        if let storedProvider {
            resolvedProvider = storedProvider
        } else if storedURL.contains("deepseek") {
            resolvedProvider = .deepseek
        } else if storedURL.contains("groq") {
            resolvedProvider = .groq
        } else if storedURL.contains("11434") {
            resolvedProvider = .ollama
        } else {
            resolvedProvider = .openai
        }

        let storedModel = defaults.string(forKey: Keys.model) ?? resolvedProvider.defaultModel
        let resolvedModel: String
        if resolvedProvider == .deepseek, ["deepseek-chat", "deepseek-reasoner"].contains(storedModel) {
            resolvedModel = "deepseek-v4-flash"
        } else {
            resolvedModel = storedModel
        }

        provider = resolvedProvider
        baseURL = storedURL
        model = resolvedModel
        let storedMax = defaults.integer(forKey: Keys.maxClipboard)
        maxClipboardItems = storedMax > 0 ? storedMax : 50
        translateTo = defaults.string(forKey: Keys.translateTo) ?? "English"
        let storedWidth = defaults.double(forKey: Keys.notchWidth)
        notchWidth = storedWidth == 0 ? 600 : min(max(storedWidth, 520), 760)
        jevAPIKey = KeychainStore.get(account: Keys.jev) ?? ""

        let account = Keys.account(for: resolvedProvider)
        apiKey = KeychainStore.get(account: account)
            ?? KeychainStore.get(account: Keys.legacyAccount)
            ?? ""
        if apiKey.isEmpty == false, KeychainStore.get(account: account) == nil {
            KeychainStore.set(apiKey, account: account)
        }

        isLoading = false
    }

    @discardableResult
    func apply(_ change: SettingsChange) -> String {
        var parts: [String] = []
        if let provider = change.provider {
            self.provider = provider
            parts.append("Provider is \(provider.title).")
        }
        if let url = change.baseURL, !url.isEmpty {
            baseURL = url
            parts.append("Base URL updated.")
        }
        if let model = change.model, !model.isEmpty {
            self.model = model
            parts.append("Model is \(model).")
        }
        if let key = change.apiKey {
            apiKey = key
            parts.append("API key saved.")
        }
        if let language = change.translateTo, !language.isEmpty {
            translateTo = language
            parts.append("Translate target is \(language).")
        }
        if provider.needsKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Paste your \(provider.title) API key in Settings to finish.")
        }
        return parts.isEmpty ? "No settings changed." : parts.joined(separator: " ")
    }

    private enum Keys {
        static let provider = "notch.chat.provider"
        static let baseURL = "notch.chat.baseURL"
        static let model = "notch.chat.model"
        static let maxClipboard = "notch.clipboard.maxItems"
        static let translateTo = "notch.clipboard.translateTo"
        static let notchWidth = "notch.island.width"
        static let legacyAccount = "openai-compatible"
        static let jev = "jev"

        static func account(for provider: AIProvider) -> String {
            "provider-\(provider.rawValue)"
        }
    }
}
