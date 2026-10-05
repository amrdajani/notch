import SwiftUI

struct ChatView: View {
    @Bindable var chat: ChatStore
    var settings: SettingsStore
    @Bindable var viewModel: NotchViewModel
    var voice: VoiceListener
    var onRequestKey: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !settings.isConfigured {
                Button {
                    viewModel.showingSettings = true
                    viewModel.isPinned = true
                    onRequestKey()
                } label: {
                    setupHint
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if chat.messages.isEmpty {
                            emptyState
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        ForEach(chat.messages) { message in
                            Group {
                                if message.role == .assistant, message.text.isEmpty, chat.isSending {
                                    typingBubble
                                } else {
                                    bubble(message)
                                }
                            }
                            .id(message.id)
                            .transition(bubbleTransition(for: message.role))
                        }
                    }
                    .padding(.horizontal, 2)
                    .animation(.spring(response: 0.36, dampingFraction: 0.84), value: chat.messages.count)
                }
                .onChange(of: chat.messages.count) {
                    if let last = chat.messages.last {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chat.messages.last?.text) {
                    if let last = chat.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let error = chat.errorMessage ?? voice.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            composer
        }
    }

    private var setupHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "key")
            Text("Add an API key in Settings to chat.")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .glassPanel(radius: 12)
        .islandTappable()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ask anything")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Ask anything, or change settings: “use DeepSeek”.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let fromUser = message.role == .user
        let streaming = chat.isSending && !fromUser && message.id == chat.messages.last?.id
        return HStack {
            if fromUser { Spacer(minLength: 24) }
            HStack(alignment: .bottom, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                if streaming, !message.text.isEmpty {
                    streamingCaret
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                fromUser ? Theme.bubbleUser : Theme.bubbleAssistant,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .textSelection(.enabled)
            if !fromUser { Spacer(minLength: 24) }
        }
    }

    private func bubbleTransition(for role: ChatMessage.Role) -> AnyTransition {
        let edge: Edge = role == .user ? .trailing : .leading
        let anchor: UnitPoint = role == .user ? .bottomTrailing : .bottomLeading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: anchor)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }

    private var streamingCaret: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Capsule()
                .fill(Theme.accent)
                .frame(width: 1.5, height: 11)
                .opacity(on ? 1 : 0)
        }
    }

    private var typingBubble: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(delay: Double(index) * 0.15)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.bubbleAssistant, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 24)
        }
    }

    private var composer: some View {
        HStack(spacing: 6) {
            TextField("Message", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassPanel(radius: 14)
                .onSubmit {
                    Task { await submit() }
                }
                .onChange(of: chat.draft) {
                    if !chat.draft.isEmpty {
                        viewModel.isPinned = true
                        viewModel.isChatFocused = true
                    }
                }
                .onChange(of: voice.transcript) {
                    if voice.isListening, !voice.transcript.isEmpty {
                        chat.draft = voice.transcript
                    }
                }

            Button {
                viewModel.isPinned = true
                viewModel.isChatFocused = true
                onRequestKey()
                Task { await voice.toggle() }
            } label: {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(voice.isListening ? Color(red: 1.0, green: 0.40, blue: 0.44) : Theme.muted)
                    .frame(width: 22, height: 22)
                    .islandTappable()
            }
            .buttonStyle(.plain)
            .help(voice.isListening ? "Stop listening" : "Speak")

            if chat.isSending {
                Button {
                    chat.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.44))
                        .islandTappable()
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button {
                    Task { await submit() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(chat.canSend ? Theme.accent : Theme.muted)
                        .islandTappable()
                }
                .buttonStyle(.plain)
                .disabled(!chat.canSend)
            }

            if !chat.messages.isEmpty {
                Button {
                    chat.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Clear chat")
            }
        }
    }

    private func submit() async {
        if voice.isListening {
            voice.stop()
        }
        await chat.send()
    }
}

private struct TypingDot: View {
    var delay: Double
    @State private var lifted = false

    var body: some View {
        Circle()
            .fill(Theme.accent.opacity(0.9))
            .frame(width: 5, height: 5)
            .offset(y: lifted ? -3 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true).delay(delay)) {
                    lifted = true
                }
            }
    }
}
