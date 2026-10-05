import SwiftUI

struct ActivityEvent: Identifiable {
    let id = UUID()
    let date: Date
    let symbol: String
    let text: String
    let tint: Color
}

/// A lightweight, in-app "notifications" feed — a rolling log of things the
/// app does, shown on the dashboard. No system permissions involved.
@MainActor
@Observable
final class ActivityStore {
    private(set) var events: [ActivityEvent] = []
    private let limit = 40

    func log(_ symbol: String, _ text: String, tint: Color = Theme.accent) {
        // Skip immediate duplicates (same text back to back).
        if events.first?.text == text { return }
        events.insert(ActivityEvent(date: Date(), symbol: symbol, text: text, tint: tint), at: 0)
        if events.count > limit {
            events = Array(events.prefix(limit))
        }
    }

    func clear() {
        events.removeAll()
    }
}
