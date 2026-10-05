import SwiftUI

struct NotchRootView: View {
    @Bindable var viewModel: NotchViewModel
    var settings: SettingsStore
    var clipboard: ClipboardStore
    var clipboardAI: ClipboardAIStore
    var chat: ChatStore
    var voice: VoiceListener
    var capture: ScreenCaptureStore
    var lecture: LectureNotesStore
    var schedule: ScheduleStore
    var nowPlaying: NowPlayingStore
    var activity: ActivityStore
    var systemStats: SystemStatsStore
    var onRequestKey: () -> Void
    var onEscape: () -> Void
    var onActivityChange: () -> Void

    @Namespace private var dockNamespace

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                if viewModel.isExpanded {
                    NotchShape(topRadius: viewModel.topRadius, bottomRadius: viewModel.bottomRadius)
                        .fill(Theme.surface)
                        .padding(.horizontal, viewModel.shadowPadding)
                }

                Group {
                    if viewModel.isExpanded {
                        expandedContent
                            .padding(.top, viewModel.notchHeight + 4)
                            .padding(.bottom, viewModel.bottomRadius + 2)
                    } else {
                        collapsedContent
                    }
                }
                .padding(.horizontal, viewModel.isExpanded ? viewModel.shadowPadding + viewModel.topRadius + 2 : 0)
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: viewModel.isExpanded)
        }
        .environment(\.colorScheme, .dark)
        .background(Color.clear)
        .onChange(of: clipboard.lastUserCaptureID) {
            clipboardAI.prepareForCapture(clipboard.latestText)
            viewModel.flashCopied()
            if let latest = clipboard.latestText {
                activity.log("doc.on.clipboard", "Copied “\(shortPreview(latest.preview))”")
            }
            if viewModel.isExpanded {
                viewModel.select(.clipboard)
            }
        }
        .onChange(of: chat.isSending) {
            if !voice.isListening {
                viewModel.trackRequest(running: chat.isSending, succeeded: chat.errorMessage == nil)
            }
            if !chat.isSending, chat.errorMessage == nil {
                activity.log("sparkles", "Chat reply ready")
            }
        }
        .onChange(of: clipboardAI.isRunning) {
            viewModel.trackRequest(running: clipboardAI.isRunning, succeeded: clipboardAI.errorMessage == nil)
            if !clipboardAI.isRunning, clipboardAI.errorMessage == nil, clipboardAI.result != nil {
                activity.log("wand.and.stars", "Clipboard AI ready", tint: Theme.accent)
            }
        }
        .onChange(of: voice.isListening) {
            if lecture.isRecording { return }
            if voice.isListening {
                viewModel.present(.listening)
            } else if viewModel.activity == .listening, !chat.isSending {
                viewModel.clearActivity(ifMatching: .listening)
            }
        }
        .onChange(of: lecture.isRecording) {
            if lecture.isRecording {
                voice.stop()
                viewModel.present(.lecturing)
            } else if lecture.isGenerating {
                viewModel.present(.thinking)
            } else if viewModel.activity == .lecturing {
                viewModel.clearActivity(ifMatching: .lecturing)
            }
        }
        .onChange(of: lecture.isGenerating) {
            viewModel.trackRequest(running: lecture.isGenerating, succeeded: lecture.errorMessage == nil)
        }
        .onChange(of: capture.isCapturing) {
            if capture.isCapturing {
                viewModel.present(.capturing)
            } else if capture.lastImage != nil, capture.errorMessage == nil {
                viewModel.present(.done, duration: 1.8)
                activity.log("camera.fill", "Screenshot captured", tint: Color(red: 1.0, green: 0.72, blue: 0.32))
            } else {
                viewModel.clearActivity(ifMatching: .capturing)
            }
        }
        .onChange(of: capture.importGeneration) {
            if capture.importGeneration > 0, !capture.isCapturing {
                viewModel.present(.copied, duration: 1.8)
                if viewModel.isExpanded {
                    viewModel.select(.capture)
                }
            }
        }
        .onChange(of: schedule.currentMeeting?.id) {
            syncMeetingActivity()
        }
        .onChange(of: schedule.collapsedText) {
            onActivityChange()
        }
        .onChange(of: viewModel.activity) {
            onActivityChange()
        }
        .onChange(of: settings.notchWidth) {
            viewModel.isPinned = true
            onActivityChange()
        }
        .onChange(of: nowPlaying.isAvailable) {
            viewModel.showsMediaGlance = nowPlaying.isAvailable
            onActivityChange()
        }
    }

    private var collapsedContent: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    if viewModel.activity.isIdle, nowPlaying.isAvailable {
                        MusicVisualizer(isPlaying: nowPlaying.isPlaying, maxHeight: 8)
                    } else {
                        Image(systemName: viewModel.activity.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(viewModel.activity.tint)
                            .symbolEffect(.pulse, options: .repeating, isActive: viewModel.activity.isLive)
                    }
                    Text(leftCollapsedTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewModel.activity == .idle ? Theme.text.opacity(0.78) : Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: max(viewModel.notchWidth - 24, 72))

                Group {
                    if viewModel.activity.isIdle, nowPlaying.isAvailable {
                        Button {
                            nowPlaying.playPause()
                        } label: {
                            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if viewModel.activity.isIdle {
                        collapsedGlance
                    } else if viewModel.activity == .lecturing {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(lecture.elapsedLabel)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(viewModel.activity.tint)
                        }
                    } else if viewModel.activity == .meeting, let meeting = schedule.currentMeeting {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(ScheduleFormat.countdown(to: meeting.end))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(viewModel.activity.tint)
                        }
                    } else {
                        LiveAccessory(activity: viewModel.activity)
                    }
                }
                .padding(.trailing, 10)
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: viewModel.notchHeight)
            .padding(.bottom, viewModel.collapsedHoverDrop)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .clipShape(NotchShape(topRadius: 0, bottomRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.activity)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: viewModel.isHovered)
    }

    private var expandedContent: some View {
        VStack(spacing: 8) {
            header

            Group {
                if viewModel.showingSettings {
                    SettingsView(settings: settings, onRequestKey: onRequestKey)
                } else {
                    switch viewModel.selectedTab {
                    case .home:
                        DashboardView(
                            viewModel: viewModel,
                            settings: settings,
                            clipboard: clipboard,
                            capture: capture,
                            lecture: lecture,
                            schedule: schedule,
                            activity: activity,
                            systemStats: systemStats
                        )
                    case .chat:
                        ChatView(chat: chat, settings: settings, viewModel: viewModel, voice: voice, onRequestKey: onRequestKey)
                    case .clipboard:
                        ClipboardView(store: clipboard, ai: clipboardAI, settings: settings, viewModel: viewModel)
                    case .capture:
                        CaptureView(store: capture)
                    case .notes:
                        LectureNotesView(
                            lecture: lecture,
                            settings: settings,
                            viewModel: viewModel,
                            voice: voice,
                            onRequestKey: onRequestKey,
                            clipboardText: clipboard.latestText?.text ?? ""
                        )
                    case .calendar:
                        CalendarView(schedule: schedule, viewModel: viewModel, onRequestKey: onRequestKey)
                    case .todos:
                        TodoListView(schedule: schedule, viewModel: viewModel, onRequestKey: onRequestKey)
                    case .dayProgress:
                        DayProgressView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            dock
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.activity.isIdle ? "sparkles" : viewModel.activity.symbol)
                    .foregroundStyle(viewModel.activity.isIdle ? Theme.accent : viewModel.activity.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: viewModel.activity.isLive)
                Text(viewModel.headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(viewModel.showingSettings ? "Settings" : viewModel.selectedTab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentMuted, in: Capsule())

                Spacer()

                headerButton("gearshape", active: viewModel.showingSettings, help: "Settings") {
                    viewModel.toggleSettings()
                    viewModel.isPinned = true
                    onRequestKey()
                }
                headerButton(viewModel.isPinned ? "pin.fill" : "pin", active: viewModel.isPinned, help: viewModel.isPinned ? "Unpin" : "Keep open") {
                    viewModel.isPinned.toggle()
                }
                headerButton("xmark", active: false, help: "Collapse", action: onEscape)
            }

            NowPlayingBar(store: nowPlaying)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func headerButton(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Theme.muted)
                .frame(width: 22, height: 22)
                .background(active ? Theme.accentMuted : Theme.faint, in: Circle())
                .islandTappable()
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }

    private var dock: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                let selected = !viewModel.showingSettings && viewModel.selectedTab == tab
                Button {
                    viewModel.select(tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                        .frame(width: 30, height: 26)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.accentMuted)
                                    .matchedGeometryEffect(id: "dockSelection", in: dockNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help(tab.title)
            }
        }
        .padding(.vertical, 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: viewModel.selectedTab)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: viewModel.showingSettings)
    }

    private var leftCollapsedTitle: String {
        if viewModel.activity.isIdle, nowPlaying.isAvailable {
            return nowPlaying.title
        }
        return viewModel.activity == .idle ? "Notch" : viewModel.activity.title
    }

    private var collapsedGlance: some View {
        let text = truncatedGlance(schedule.collapsedText)
        return HStack(spacing: 6) {
            Image(systemName: schedule.collapsedText == nil ? "clipboard" : schedule.collapsedSymbol)
                .font(.system(size: 9, weight: .medium))
            Text(text ?? "\(clipboard.items.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .monospacedDigit()
        }
        .foregroundStyle(Theme.accent)
    }

    private func shortPreview(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count <= 24 ? clean : String(clean.prefix(23)) + "…"
    }

    private func truncatedGlance(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if text.count <= 16 { return text }
        return String(text.prefix(15)) + "…"
    }

    private func syncMeetingActivity() {
        if lecture.isRecording || capture.isCapturing || voice.isListening || chat.isSending { return }
        if schedule.currentMeeting != nil {
            viewModel.present(.meeting)
        } else if viewModel.activity == .meeting {
            viewModel.clearActivity(ifMatching: .meeting)
        }
    }
}
