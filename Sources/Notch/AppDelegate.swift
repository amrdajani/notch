import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var clipboard = ClipboardStore()
    private lazy var clipboardAI = ClipboardAIStore(settings: settings)
    private lazy var chat = ChatStore(settings: settings)
    private let voice = VoiceListener()
    private lazy var capture = ScreenCaptureStore(clipboard: clipboard)
    private lazy var schedule = ScheduleStore()
    private lazy var lecture = LectureNotesStore(settings: settings, schedule: schedule)
    private let nowPlaying = NowPlayingStore()
    private let activity = ActivityStore()
    private let systemStats = SystemStatsStore()
    private var notchWindow: NotchWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start(maxItems: settings.maxClipboardItems)
        capture.startWatching()
        schedule.start()
        nowPlaying.start()
        systemStats.start()
        installMenuBar()
        notchWindow = NotchWindow(
            settings: settings,
            clipboard: clipboard,
            chat: chat,
            clipboardAI: clipboardAI,
            voice: voice,
            capture: capture,
            lecture: lecture,
            schedule: schedule,
            nowPlaying: nowPlaying,
            activity: activity,
            systemStats: systemStats
        )
        GlobalHotKey.shared.onPressed = { [weak self] in
            self?.notchWindow?.toggle()
        }
        GlobalHotKey.shared.onClipToNote = { [weak self] in
            self?.noteFromClipboard()
        }
        GlobalHotKey.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKey.shared.unregister()
        lecture.cancel()
        voice.stop()
        capture.stopWatching()
        clipboard.stop()
        schedule.stop()
        nowPlaying.stop()
        systemStats.stop()
        notchWindow?.destroy()
        notchWindow = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func installMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Notch")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Toggle Notch", action: #selector(toggleNotch), keyEquivalent: " ")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(menuItem("Expand", action: #selector(expandNotch), key: "e"))
        menu.addItem(menuItem("Collapse", action: #selector(collapseNotch), key: "w"))
        menu.addItem(menuItem("Capture Screen", action: #selector(captureScreen), key: "3"))
        menu.addItem(menuItem("Capture Selection", action: #selector(captureSelection), key: "4"))
        menu.addItem(menuItem("Lecture Notes", action: #selector(toggleLecture), key: "l"))
        let clipNote = NSMenuItem(title: "Note from Clipboard", action: #selector(noteFromClipboard), keyEquivalent: "n")
        clipNote.keyEquivalentModifierMask = [.control, .option]
        clipNote.target = self
        menu.addItem(clipNote)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Notch", action: #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleNotch() {
        notchWindow?.toggle()
    }

    @objc private func expandNotch() {
        notchWindow?.expand(pin: true)
    }

    @objc private func collapseNotch() {
        notchWindow?.collapse()
    }

    @objc private func captureScreen() {
        Task { await capture.capture(.display) }
    }

    @objc private func captureSelection() {
        Task { await capture.capture(.selection) }
    }

    @objc private func toggleLecture() {
        notchWindow?.showNotes()
        Task { await lecture.toggle() }
    }

    @objc private func noteFromClipboard() {
        notchWindow?.showNotes()
        if let text = clipboard.latestText?.text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lecture.createNote(body: text)
        } else {
            lecture.createNote()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
