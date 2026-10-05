import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case chat
    case clipboard
    case capture
    case notes
    case calendar
    case todos
    case dayProgress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .clipboard: "Clip"
        case .capture: "Capture"
        case .notes: "Notes"
        case .calendar: "Calendar"
        case .todos: "To-dos"
        case .dayProgress: "Day"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .chat: "sparkles"
        case .clipboard: "clipboard"
        case .capture: "camera"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .todos: "checklist"
        case .dayProgress: "sun.max"
        }
    }
}

@MainActor
@Observable
final class NotchViewModel {
    var isExpanded = false
    var isHovered = false
    var showsMediaGlance = false
    var isPinned = false
    var isChatFocused = false
    var showingSettings = false
    var selectedTab: NotchTab = .home
    var activity: NotchActivity = .idle
    private var activityTask: Task<Void, Never>?
    private var activityToken = 0

    var geometry: NotchGeometry
    let shadowPadding: CGFloat = 18

    var notchWidth: CGFloat { geometry.width }
    var notchHeight: CGFloat { geometry.height }

    var shouldStayOpen: Bool {
        isPinned || isChatFocused
    }

    var headerTitle: String {
        if !activity.isIdle { return activity.title }
        if showingSettings { return "Notch" }
        return "Notch"
    }

    var topRadius: CGFloat { isExpanded ? 18 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 22 : 13 }
    var collapsedHoverDrop: CGFloat { isHovered ? 5 : 0 }

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func select(_ tab: NotchTab) {
        showingSettings = false
        selectedTab = tab
    }

    func toggleSettings() {
        showingSettings.toggle()
    }

    func present(_ activity: NotchActivity, duration: TimeInterval? = nil) {
        activityToken += 1
        let token = activityToken
        activityTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.activity = activity
        }
        guard let duration else { return }
        activityTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, activityToken == token else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                self.activity = .idle
            }
        }
    }

    func clearActivity(ifMatching match: NotchActivity? = nil) {
        if let match, activity != match { return }
        present(.idle)
    }

    func flashCopied() {
        present(.copied, duration: 2)
    }

    func trackRequest(running: Bool, succeeded: Bool) {
        if running {
            present(.downloading)
            let token = activityToken
            activityTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, activityToken == token, activity == .downloading else { return }
                present(.thinking)
            }
        } else if succeeded {
            present(.done, duration: 1.8)
        } else {
            present(.idle)
        }
    }
}
