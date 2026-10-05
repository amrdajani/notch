import AppKit
import EventKit
import Foundation
import SwiftUI

enum ReminderFilter: String, CaseIterable, Identifiable {
    case day
    case overdue
    case upcoming
    case noDate
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .overdue: "Overdue"
        case .upcoming: "Upcoming"
        case .noDate: "No date"
        case .all: "All"
        }
    }
}

enum TodoPane: Equatable {
    case list
    case detail(String)
    case compose
    case trash
}

struct CalendarItem: Identifiable {
    let id: String
    var title: String
    var location: String
    var notes: String
    var calendarName: String
    var color: Color
    var start: Date
    var end: Date
    var isAllDay: Bool

    var isHappening: Bool {
        let now = Date()
        return start <= now && now < end
    }

    var searchBlob: String {
        "\(title) \(location) \(notes) \(calendarName)"
    }
}

struct ReminderItem: Identifiable {
    let id: String
    var title: String
    var notes: String
    var calendarName: String
    var color: Color
    var isCompleted: Bool
    var dueDate: Date?
    var startDate: Date?
    var alarmDate: Date?

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Date()
    }

    var hasNoDate: Bool { dueDate == nil && startDate == nil }

    var searchBlob: String {
        "\(title) \(notes) \(calendarName)"
    }
}

struct TrashedReminder: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var startDate: Date?
    var calendarIdentifier: String?
    var deletedAt: Date
    var retainUntil: Date
}

struct ReminderDraft {
    var editingID: String?
    var title = ""
    var notes = ""
    var hasDue = false
    var due = Date()
    var hasSchedule = false
    var start = Date()
    var end = Date().addingTimeInterval(3600)

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
@Observable
final class ScheduleStore {
    private let store = EKEventStore()
    private var reminderFetch: Any?
    private var changeObserver: NSObjectProtocol?
    private var ticker: Task<Void, Never>?
    private let trashURL: URL
    private let trashRetention: TimeInterval = 60 * 60 * 24 * 30

    var events: [CalendarItem] = []
    var reminders: [ReminderItem] = []
    var trash: [TrashedReminder] = []
    var selectedDay = Date()
    var displayedMonth = Date()
    var search = ""
    var reminderFilter: ReminderFilter = .day
    var todoSearch = ""
    var todoPane: TodoPane = .list
    var draft = ReminderDraft()
    var selectedEventID: String?
    var eventsAllowed = false
    var remindersAllowed = false
    var errorMessage: String?
    var clock = Date()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        trashURL = support.appendingPathComponent("reminder-trash.json")
        loadTrash()
        refreshAuthorization()
    }

    func start() {
        observeChanges()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshDerived()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        Task { await reload() }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        reminderFetch = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }

    var hasAnyAccess: Bool { eventsAllowed || remindersAllowed }

    var selectedEvent: CalendarItem? {
        events.first { $0.id == selectedEventID }
    }

    var currentMeeting: CalendarItem? {
        _ = clock
        return events.first(where: \.isHappening)
    }

    var nextEvent: CalendarItem? {
        _ = clock
        let now = Date()
        return events
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
            .first
    }

    var todayEvents: [CalendarItem] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: Date()) || $0.isHappening }
            .sorted { $0.start < $1.start }
    }

    var overdueReminders: [ReminderItem] {
        reminders.filter(\.isOverdue)
    }

    var openReminders: [ReminderItem] {
        reminders.filter { !$0.isCompleted }.sorted(by: Self.sortReminders)
    }

    var doneReminders: [ReminderItem] {
        reminders.filter(\.isCompleted)
    }

    var visibleTodos: [ReminderItem] {
        let query = todoSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = openReminders
        guard !query.isEmpty else { return base }
        return base.filter { $0.searchBlob.localizedCaseInsensitiveContains(query) }
    }

    var visibleDone: [ReminderItem] {
        let query = todoSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return doneReminders }
        return doneReminders.filter { $0.searchBlob.localizedCaseInsensitiveContains(query) }
    }

    var agendaItems: [AgendaEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = selectedDay
        var entries: [AgendaEntry] = []

        func matches(_ blob: String) -> Bool {
            query.isEmpty || blob.localizedCaseInsensitiveContains(query)
        }

        switch reminderFilter {
        case .day:
            entries.append(contentsOf: events.compactMap { event in
                guard Calendar.current.isDate(event.start, inSameDayAs: day) || event.isHappening && Calendar.current.isDate(day, inSameDayAs: Date()) else { return nil }
                guard matches(event.searchBlob) else { return nil }
                return .event(event)
            })
            entries.append(contentsOf: reminders.compactMap { item in
                guard !item.isCompleted, let due = item.dueDate, Calendar.current.isDate(due, inSameDayAs: day) else { return nil }
                guard matches(item.searchBlob) else { return nil }
                return .reminder(item)
            })
        case .overdue:
            entries.append(contentsOf: overdueReminders.compactMap { item in
                matches(item.searchBlob) ? .reminder(item) : nil
            })
        case .upcoming:
            let now = Date()
            entries.append(contentsOf: events.compactMap { event in
                guard event.start > now else { return nil }
                guard matches(event.searchBlob) else { return nil }
                return .event(event)
            })
            entries.append(contentsOf: reminders.compactMap { item in
                guard !item.isCompleted, let due = item.dueDate, due > now else { return nil }
                guard matches(item.searchBlob) else { return nil }
                return .reminder(item)
            })
        case .noDate:
            entries.append(contentsOf: reminders.compactMap { item in
                guard !item.isCompleted, item.hasNoDate, matches(item.searchBlob) else { return nil }
                return .reminder(item)
            })
        case .all:
            entries.append(contentsOf: events.compactMap { event in
                matches(event.searchBlob) ? .event(event) : nil
            })
            entries.append(contentsOf: reminders.compactMap { item in
                guard !item.isCompleted, matches(item.searchBlob) else { return nil }
                return .reminder(item)
            })
        }

        return entries.sorted { $0.sortDate < $1.sortDate }
    }

    var collapsedKind: CollapsedGlance {
        _ = clock
        if let meeting = currentMeeting {
            return .meeting(meeting)
        }
        if let next = nextEvent, next.start.timeIntervalSinceNow < 2 * 60 * 60 {
            return .upcoming(next)
        }
        if !overdueReminders.isEmpty {
            return .overdue(overdueReminders.count)
        }
        let count = todayEvents.count
        if count > 0 {
            return .events(count)
        }
        if let first = openReminders.first {
            return .task(first)
        }
        return .none
    }

    var collapsedText: String? {
        switch collapsedKind {
        case .none: nil
        case .meeting(let event): event.title
        case .upcoming(let event): event.title
        case .overdue(let count): "\(count) overdue"
        case .events(let count): "\(count) events"
        case .task(let item): item.title
        }
    }

    var collapsedSymbol: String {
        switch collapsedKind {
        case .none: "clipboard"
        case .meeting, .upcoming, .events: "calendar"
        case .overdue, .task: "checklist"
        }
    }

    func requestAccess() async {
        errorMessage = nil
        do {
            eventsAllowed = try await store.requestFullAccessToEvents()
        } catch {
            errorMessage = error.localizedDescription
            eventsAllowed = false
        }
        do {
            remindersAllowed = try await store.requestFullAccessToReminders()
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
            remindersAllowed = false
        }
        refreshAuthorization()
        await reload()
        migrateLegacyTodosIfNeeded()
    }

    func reload() async {
        refreshAuthorization()
        purgeExpiredTrash()
        if eventsAllowed { loadEvents() }
        if remindersAllowed { fetchReminders() }
        refreshDerived()
    }

    func selectDay(_ date: Date) {
        selectedDay = date
        displayedMonth = date
        reminderFilter = .day
        selectedEventID = nil
    }

    func goToday() {
        selectDay(Date())
    }

    func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    func reminder(id: String) -> ReminderItem? {
        reminders.first { $0.id == id }
    }

    func beginCompose() {
        draft = ReminderDraft()
        todoPane = .compose
    }

    func beginEdit(_ id: String) {
        guard let item = reminder(id: id) else { return }
        draft = ReminderDraft(
            editingID: id,
            title: item.title,
            notes: item.notes,
            hasDue: item.dueDate != nil,
            due: item.dueDate ?? Date(),
            hasSchedule: item.startDate != nil,
            start: item.startDate ?? Date(),
            end: item.dueDate ?? Date().addingTimeInterval(3600)
        )
        todoPane = .compose
    }

    func saveDraft() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, remindersAllowed else { return }
        let due = draft.hasDue ? draft.due : (draft.hasSchedule ? draft.end : nil)
        let start = draft.hasSchedule ? draft.start : nil
        if let id = draft.editingID, let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
            apply(draft, to: existing, title: title, due: due, start: start)
            try? store.save(existing, commit: true)
            todoPane = .detail(id)
        } else if let created = addReminder(title: title, notes: draft.notes, due: due, start: start) {
            todoPane = .detail(created)
        } else {
            todoPane = .list
        }
        draft = ReminderDraft()
        fetchReminders()
    }

    @discardableResult
    func addReminder(title: String, notes: String = "", due: Date? = nil, start: Date? = nil, reload: Bool = true) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard remindersAllowed, let calendar = store.defaultCalendarForNewReminders() else {
            pendingTitles.append(trimmed)
            return nil
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        apply(ReminderDraft(title: trimmed, notes: notes), to: reminder, title: trimmed, due: due, start: start)
        do {
            try store.save(reminder, commit: true)
            if reload { fetchReminders() }
            return reminder.calendarItemIdentifier
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleReminder(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted.toggle()
        reminder.completionDate = reminder.isCompleted ? Date() : nil
        try? store.save(reminder, commit: true)
        fetchReminders()
    }

    func deleteReminder(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        let snapshot = TrashedReminder(
            id: UUID(),
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            dueDate: Self.date(from: reminder.dueDateComponents),
            startDate: Self.date(from: reminder.startDateComponents),
            calendarIdentifier: reminder.calendar?.calendarIdentifier,
            deletedAt: Date(),
            retainUntil: Date().addingTimeInterval(trashRetention)
        )
        do {
            try store.remove(reminder, commit: true)
            trash.insert(snapshot, at: 0)
            persistTrash()
            if case .detail(id) = todoPane { todoPane = .list }
            fetchReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(_ item: TrashedReminder) {
        _ = addReminder(title: item.title, notes: item.notes, due: item.dueDate, start: item.startDate)
        trash.removeAll { $0.id == item.id }
        persistTrash()
    }

    func purgeTrash() {
        trash.removeAll()
        persistTrash()
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    func openRemindersApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }

    private var pendingTitles: [String] {
        get { UserDefaults.standard.stringArray(forKey: "notch.reminders.pending") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "notch.reminders.pending") }
    }

    private func apply(_ draft: ReminderDraft, to reminder: EKReminder, title: String, due: Date?, start: Date?) {
        reminder.title = title
        reminder.notes = draft.notes
        let calendar = Calendar.current
        let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        reminder.dueDateComponents = due.map { calendar.dateComponents(units, from: $0) }
        reminder.startDateComponents = start.map { calendar.dateComponents(units, from: $0) }
        if let alarms = reminder.alarms {
            for alarm in alarms {
                reminder.removeAlarm(alarm)
            }
        }
        if let due {
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
    }

    private func loadEvents() {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: displayedMonth)) ?? displayedMonth
        let finish = calendar.date(byAdding: .month, value: 3, to: start) ?? start.addingTimeInterval(90 * 24 * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: finish, calendars: nil)
        events = store.events(matching: predicate).map { event in
            CalendarItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Event",
                location: event.structuredLocation?.title ?? event.location ?? "",
                notes: event.notes ?? "",
                calendarName: event.calendar?.title ?? "Calendar",
                color: Self.color(event.calendar?.cgColor),
                start: event.startDate ?? Date(),
                end: event.endDate ?? Date(),
                isAllDay: event.isAllDay
            )
        }
        .sorted { $0.start < $1.start }
    }

    private func fetchReminders() {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars.isEmpty ? nil : calendars)
        reminderFetch = store.fetchReminders(matching: predicate) { [weak self] items in
            Task { @MainActor in
                guard let self else { return }
                self.reminders = (items ?? []).map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Reminder",
                        notes: reminder.notes ?? "",
                        calendarName: reminder.calendar?.title ?? "Reminders",
                        color: Self.color(reminder.calendar?.cgColor),
                        isCompleted: reminder.isCompleted,
                        dueDate: Self.date(from: reminder.dueDateComponents),
                        startDate: Self.date(from: reminder.startDateComponents),
                        alarmDate: reminder.alarms?.compactMap(\.absoluteDate).min()
                    )
                }
                self.flushPending()
                self.refreshDerived()
            }
        }
    }

    private func flushPending() {
        let titles = pendingTitles
        guard !titles.isEmpty, remindersAllowed else { return }
        pendingTitles = []
        for title in titles {
            _ = addReminder(title: title, reload: false)
        }
        fetchReminders()
    }

    private func refreshAuthorization() {
        eventsAllowed = Self.isAllowed(EKEventStore.authorizationStatus(for: .event))
        remindersAllowed = Self.isAllowed(EKEventStore.authorizationStatus(for: .reminder))
    }

    private func refreshDerived() {
        clock = Date()
    }

    private func observeChanges() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reload()
            }
        }
    }

    private func migrateLegacyTodosIfNeeded() {
        guard remindersAllowed, !UserDefaults.standard.bool(forKey: "notch.reminders.migrated") else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("todos.json")
        if let data = try? Data(contentsOf: support),
           let items = try? JSONDecoder().decode([TodoItem].self, from: data) {
            for item in items where !item.isDone {
                _ = addReminder(title: item.text, reload: false)
            }
            fetchReminders()
            try? FileManager.default.removeItem(at: support)
        }
        UserDefaults.standard.set(true, forKey: "notch.reminders.migrated")
    }

    private func loadTrash() {
        guard
            let data = try? Data(contentsOf: trashURL),
            let decoded = try? JSONDecoder().decode([TrashedReminder].self, from: data)
        else { return }
        trash = decoded
        purgeExpiredTrash()
    }

    private func persistTrash() {
        guard let data = try? JSONEncoder().encode(trash) else { return }
        try? data.write(to: trashURL, options: .atomic)
    }

    private func purgeExpiredTrash() {
        let now = Date()
        trash.removeAll { $0.retainUntil < now }
        persistTrash()
    }

    private static func date(from components: DateComponents?) -> Date? {
        guard var components else { return nil }
        components.calendar = components.calendar ?? Calendar.current
        components.timeZone = components.timeZone ?? TimeZone.current
        return components.date
    }

    private static func isAllowed(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    private static func color(_ cg: CGColor?) -> Color {
        guard let cg, let ns = NSColor(cgColor: cg) else { return Theme.accent }
        return Color(nsColor: ns)
    }

    private static func sortReminders(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

enum AgendaEntry: Identifiable {
    case event(CalendarItem)
    case reminder(ReminderItem)

    var id: String {
        switch self {
        case .event(let item): "event-\(item.id)"
        case .reminder(let item): "reminder-\(item.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .event(let item): item.start
        case .reminder(let item): item.dueDate ?? .distantFuture
        }
    }
}

enum CollapsedGlance {
    case none
    case meeting(CalendarItem)
    case upcoming(CalendarItem)
    case overdue(Int)
    case events(Int)
    case task(ReminderItem)
}

enum ScheduleFormat {
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d. MMM yyyy"
        return formatter
    }()

    static let longStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func range(_ start: Date, _ end: Date, allDay: Bool) -> String {
        if allDay { return "All day" }
        return "\(time(start)) – \(time(end))"
    }

    static func countdown(to date: Date, from now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d"
    }

    static func remaining(_ interval: TimeInterval) -> String {
        let days = max(0, Int(interval / 86_400))
        if days == 0 { return "today" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}
