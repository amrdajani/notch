import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchWindow {
    private var panel: NotchPanel
    private var geometry: NotchGeometry
    private let viewModel: NotchViewModel
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var revealObserver: NSObjectProtocol?
    private var collapseWork: DispatchWorkItem?
    private var lastPointerCheck: CFTimeInterval = 0

    private let settings: SettingsStore
    private let clipboard: ClipboardStore
    private let schedule: ScheduleStore
    private var suppressHover = false
    private let wingExtension: CGFloat = 168

    private var expandedSize: NSSize {
        NSSize(width: CGFloat(settings.notchWidth), height: 530)
    }

    init(
        settings: SettingsStore,
        clipboard: ClipboardStore,
        chat: ChatStore,
        clipboardAI: ClipboardAIStore,
        voice: VoiceListener,
        capture: ScreenCaptureStore,
        lecture: LectureNotesStore,
        schedule: ScheduleStore,
        nowPlaying: NowPlayingStore,
        activity: ActivityStore,
        systemStats: SystemStatsStore
    ) {
        self.settings = settings
        self.clipboard = clipboard
        self.schedule = schedule
        geometry = NotchGeometry.current()
        viewModel = NotchViewModel(geometry: geometry)

        var frame = geometry.collapsedFrame(wingExtension: wingExtension)
        frame.size.height += 10
        frame.origin.y -= 10
        panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let root = NotchRootView(
            viewModel: viewModel,
            settings: settings,
            clipboard: clipboard,
            clipboardAI: clipboardAI,
            chat: chat,
            voice: voice,
            capture: capture,
            lecture: lecture,
            schedule: schedule,
            nowPlaying: nowPlaying,
            activity: activity,
            systemStats: systemStats,
            onRequestKey: { [weak panel] in
                guard let panel else { return }
                panel.allowsKey = true
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onEscape: { [weak self] in
                self?.collapse()
            },
            onActivityChange: { [weak self] in
                self?.syncFrame()
            }
        )

        let host = NotchHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()

        installMouseMonitors()
        observeScreens()
        revealObserver = NotificationCenter.default.addObserver(
            forName: .notchRevealApp, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapse()
            }
        }

        capture.hideIsland = { [weak self] in
            await self?.prepareForCapture()
        }
        capture.showIsland = { [weak self] in
            self?.restoreAfterCapture()
        }
    }

    func expand(pin: Bool = false) {
        collapseWork?.cancel()
        if pin { viewModel.isPinned = true }
        guard !viewModel.isExpanded else { return }

        geometry = NotchGeometry.current()
        viewModel.geometry = geometry
        viewModel.isHovered = false
        viewModel.isExpanded = true
        panel.allowsKey = true
        let frame = geometry.expandedFrame(size: expandedSize, shadowPadding: viewModel.shadowPadding)
        animate(to: frame, duration: 0.38)
    }

    func toggle() {
        if viewModel.isExpanded {
            collapse()
            return
        }
        if clipboard.wasRecentlyCaptured {
            viewModel.select(.clipboard)
        }
        expand(pin: true)
        requestKey()
    }

    func showNotes() {
        viewModel.select(.notes)
        expand(pin: true)
    }

    func requestKey() {
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func collapse() {
        collapseWork?.cancel()
        viewModel.isPinned = false
        viewModel.isChatFocused = false
        viewModel.isHovered = false
        panel.allowsKey = false
        panel.resignKey()
        guard viewModel.isExpanded else { return }

        viewModel.isExpanded = false
        geometry = NotchGeometry.current()
        viewModel.geometry = geometry
        animate(to: currentCollapsedFrame(), duration: 0.32)
    }

    func destroy() {
        collapseWork?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let revealObserver { NotificationCenter.default.removeObserver(revealObserver) }
        localMonitor = nil
        globalMonitor = nil
        screenObserver = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    private func animate(to frame: NSRect, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func installMouseMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                if self.viewModel.isExpanded {
                    self.viewModel.isPinned = true
                    self.requestKey()
                } else {
                    self.expand(pin: true)
                    self.requestKey()
                }
            } else {
                self.handlePointerThrottled()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePointerThrottled()
            }
        }
    }

    private func handlePointerThrottled() {
        let now = CACurrentMediaTime()
        guard now - lastPointerCheck >= 0.03 else { return }
        lastPointerCheck = now
        handlePointer()
    }

    private func handlePointer() {
        guard !suppressHover else {
            if viewModel.isHovered { viewModel.isHovered = false }
            return
        }
        let location = NSEvent.mouseLocation
        let hitPad = panel.frame.insetBy(dx: -8, dy: -8)
        let inside = hitPad.contains(location)

        if viewModel.isExpanded {
            if viewModel.isHovered { viewModel.isHovered = false }
            if !inside { scheduleCollapse() }
            return
        }

        guard viewModel.isHovered != inside else { return }
        viewModel.isHovered = inside
    }

    private func scheduleCollapse() {
        guard !viewModel.shouldStayOpen else { return }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let padded = self.panel.frame.insetBy(dx: -12, dy: -12)
            if !padded.contains(NSEvent.mouseLocation), !self.viewModel.shouldStayOpen {
                self.collapse()
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reposition()
            }
        }
    }

    private func reposition() {
        geometry = NotchGeometry.current()
        viewModel.geometry = geometry
        let frame = viewModel.isExpanded
            ? geometry.expandedFrame(size: expandedSize, shadowPadding: viewModel.shadowPadding)
            : currentCollapsedFrame()
        panel.setFrame(frame, display: true)
    }

    private func currentCollapsedFrame() -> NSRect {
        var extra: CGFloat = 0
        if !viewModel.activity.isIdle {
            extra = 52
        } else if schedule.collapsedText != nil || viewModel.showsMediaGlance {
            extra = 40
        }
        var frame = geometry.collapsedFrame(wingExtension: wingExtension + extra)
        frame.size.height += 10
        frame.origin.y -= 10
        return frame
    }

    private func syncFrame() {
        geometry = NotchGeometry.current()
        viewModel.geometry = geometry
        if viewModel.isExpanded {
            animate(
                to: geometry.expandedFrame(size: expandedSize, shadowPadding: viewModel.shadowPadding),
                duration: 0.18
            )
        } else {
            animate(to: currentCollapsedFrame(), duration: 0.28)
        }
    }

    private func prepareForCapture() async {
        collapseWork?.cancel()
        suppressHover = true
        viewModel.present(.capturing)
        viewModel.isPinned = false
        viewModel.isChatFocused = false
        viewModel.isHovered = false
        viewModel.isExpanded = false
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func restoreAfterCapture() {
        geometry = NotchGeometry.current()
        viewModel.geometry = geometry
        panel.setFrame(currentCollapsedFrame(), display: true)
        panel.orderFrontRegardless()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            suppressHover = false
        }
    }
}
