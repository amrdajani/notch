import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var onRequestKey: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Provider")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(Array(AIProvider.allCases.prefix(3))) { provider in
                            providerChip(provider)
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(Array(AIProvider.allCases.suffix(2))) { provider in
                            providerChip(provider)
                        }
                    }
                }

                Text(settings.provider.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)

                if settings.provider == .custom {
                    field("API base URL", text: $settings.baseURL, prompt: "https://api.deepseek.com")
                }

                if !settings.provider.models.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        HStack(spacing: 4) {
                            ForEach(settings.provider.models, id: \.self) { name in
                                Button {
                                    settings.model = name
                                } label: {
                                    Text(shortModelName(name))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(settings.model == name ? Theme.accent : Theme.muted)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(settings.model == name ? Theme.accentMuted : Theme.faint)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    field("Model", text: $settings.model, prompt: settings.provider.defaultModel)
                }

                if settings.provider.needsKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        SecureField(settings.provider.keyPlaceholder, text: $settings.apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .padding(8)
                            .glassPanel(radius: 12)
                    }
                }

                field("Translate to", text: $settings.translateTo, prompt: "English")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Jev")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    SecureField("TypeSafe API key", text: $settings.jevAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .padding(8)
                        .glassPanel(radius: 12)
                    Text("Routes “open Notes” and “find a YouTube video” before chat. Get a key from TypeSafe.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Notch width")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(Int(settings.notchWidth.rounded()))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                    Slider(value: $settings.notchWidth, in: 520...760, step: 20)
                        .tint(Theme.accent)
                    Text("Width of the expanded island. Drag to resize while Settings is open.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Chat can edit these")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Text("Try “use DeepSeek”, “use deepseek-v4-flash”, or paste a key like sk-… in Chat.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Global hotkey")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Text("\(GlobalHotKey.displayName) toggles the tray. \(GlobalHotKey.clipNoteName) saves the current clipboard as a note.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                HStack {
                    Text("Clipboard history")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(settings.maxClipboardItems)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxClipboardItems) },
                        set: { settings.maxClipboardItems = Int($0) }
                    ),
                    in: 10...100,
                    step: 5
                )
                .tint(Theme.accent)
            }
            .padding(.top, 2)
        }
    }

    private func shortModelName(_ id: String) -> String {
        switch id {
        case "deepseek-v4-flash": "V4 Flash"
        case "deepseek-v4-pro": "V4 Pro"
        default: id
        }
    }

    private func providerChip(_ provider: AIProvider) -> some View {
        Button {
            settings.provider = provider
        } label: {
            Text(provider.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(settings.provider == provider ? Theme.accent : Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(settings.provider == provider ? Theme.accentMuted : Theme.faint)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .padding(8)
                .glassPanel(radius: 12)
        }
    }
}
