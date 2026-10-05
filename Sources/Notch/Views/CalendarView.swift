import SwiftUI

struct CalendarView: View {
    @Bindable var schedule: ScheduleStore
    @Bindable var viewModel: NotchViewModel
    var onRequestKey: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !schedule.hasAnyAccess {
                permission
            } else if let event = schedule.selectedEvent {
                eventDetail(event)
            } else {
                header
                filters
                if let error = schedule.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.85))
                }
                if let meeting = schedule.currentMeeting {
                    meetingBanner(meeting)
                }
                HStack(alignment: .top, spacing: 10) {
                    monthPane
                        .frame(width: 188)
                    agendaPane
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            viewModel.isPinned = true
            onRequestKey()
        }
    }

    private var permission: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
            Text("Allow Calendar and Reminders to show upcoming events here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Allow access") {
                Task { await schedule.requestAccess() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(ScheduleFormat.monthYear.string(from: schedule.displayedMonth))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Button("Today") {
                schedule.goToday()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accentMuted, in: Capsule())
            .contentShape(Capsule())

            TextField("Search events & reminders", text: $schedule.search)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .glassPanel(radius: 10)
                .onChange(of: schedule.search) {
                    if !schedule.search.isEmpty {
                        viewModel.isPinned = true
                        viewModel.isChatFocused = true
                    }
                }

            headerIcon("chevron.left") { schedule.shiftMonth(-1) }
            headerIcon("chevron.right") { schedule.shiftMonth(1) }
            headerIcon("arrow.clockwise") {
                Task { await schedule.reload() }
            }
            headerIcon("plus") {
                viewModel.select(.todos)
                schedule.beginCompose()
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 4) {
            ForEach(ReminderFilter.allCases) { filter in
                let selected = schedule.reminderFilter == filter
                Button {
                    schedule.reminderFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Theme.surface : Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selected ? Color.white : Theme.faint, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func meetingBanner(_ event: CalendarItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("In a meeting · \(event.title)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(ScheduleFormat.countdown(to: event.end) + " left")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassPanel(radius: 12)
    }

    private var monthPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ScheduleFormat.month.string(from: schedule.displayedMonth).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
            monthGrid
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(radius: 14)
    }

    private var monthGrid: some View {
        let days = monthDays
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let inMonth = Calendar.current.isDate(date, equalTo: schedule.displayedMonth, toGranularity: .month)
                        let selected = Calendar.current.isDate(date, inSameDayAs: schedule.selectedDay)
                        let today = Calendar.current.isDateInToday(date)
                        Button {
                            schedule.selectDay(date)
                        } label: {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 10, weight: selected || today ? .bold : .medium))
                                .foregroundStyle(selected ? Theme.surface : (inMonth ? Theme.text : Theme.muted.opacity(0.5)))
                                .frame(width: 22, height: 22)
                                .background(selected ? Color.white : Color.clear, in: Circle())
                                .overlay {
                                    if today, !selected {
                                        Circle().stroke(Theme.accent, lineWidth: 1)
                                    }
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 22, height: 22)
                    }
                }
            }
        }
    }

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: schedule.displayedMonth)?.start ?? schedule.displayedMonth
        let weekday = calendar.component(.weekday, from: month)
        let prefix = weekday - calendar.firstWeekday
        let pad = (prefix + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: pad)
        for day in 0..<count {
            days.append(calendar.date(byAdding: .day, value: day, to: month))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private var agendaPane: some View {
        let items = schedule.agendaItems
        return Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: schedule.reminderFilter == .day ? "calendar" : "checklist")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.muted)
                    Text(emptyTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(emptySubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items) { entry in
                            switch entry {
                            case .event(let event):
                                eventRow(event)
                            case .reminder(let item):
                                reminderRow(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        switch schedule.reminderFilter {
        case .day: "No events"
        case .overdue: "No overdue reminders"
        case .upcoming: "Nothing upcoming"
        case .noDate: "No undated reminders"
        case .all: "Nothing loaded"
        }
    }

    private var emptySubtitle: String {
        if !schedule.search.isEmpty { return "No loaded items match that search." }
        switch schedule.reminderFilter {
        case .day: return "No events or reminders on this date."
        case .overdue: return "You’re clear — nothing past due."
        case .upcoming: return "No dated reminders or events ahead."
        case .noDate: return "Every reminder has a date."
        case .all: return "Search by title, location, notes, or calendar."
        }
    }

    private func eventRow(_ event: CalendarItem) -> some View {
        Button {
            schedule.selectedEventID = event.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(event.isAllDay ? "All day" : ScheduleFormat.range(event.start, event.end, allDay: false))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(event.color)
                    .frame(width: 88, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if !event.location.isEmpty {
                        Text(event.location)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(event.isHappening ? Theme.accent : event.color)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .glassPanel(radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func reminderRow(_ item: ReminderItem) -> some View {
        Button {
            viewModel.select(.todos)
            schedule.todoPane = .detail(item.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(item.dueDate.map(ScheduleFormat.time) ?? "Remind")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.isOverdue ? Color(red: 1.0, green: 0.40, blue: 0.44) : Theme.accent)
                    .frame(width: 88, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(item.calendarName + (item.isOverdue ? " · Overdue" : ""))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .glassPanel(radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func eventDetail(_ event: CalendarItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    schedule.selectedEventID = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .labelStyle(.titleAndIcon)
                        .islandTappable()
                }
                .buttonStyle(.plain)
                Spacer()
                Text(ScheduleFormat.dayStamp.string(from: event.start))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Text(event.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            ScrollView {
                VStack(spacing: 8) {
                    meta("clock", "WHEN", ScheduleFormat.range(event.start, event.end, allDay: event.isAllDay))
                    if !event.location.isEmpty {
                        meta("mappin.and.ellipse", "LOCATION", event.location)
                    }
                    meta("calendar", "CALENDAR", event.calendarName)
                    if event.start > Date() {
                        meta("timer", "COUNTDOWN", "Starts in \(ScheduleFormat.countdown(to: event.start))")
                    } else if event.isHappening {
                        meta("timer", "REMAINING", "\(ScheduleFormat.countdown(to: event.end)) left")
                    }
                    if !event.notes.isEmpty {
                        meta("note.text", "NOTES", event.notes)
                    }
                }
            }

            Button("Open in Calendar") {
                schedule.openCalendarApp()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
    }

    private func meta(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .glassPanel(radius: 12)
    }

    private func headerIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 22, height: 22)
                .background(Theme.faint, in: Circle())
                .islandTappable()
        }
        .buttonStyle(.plain)
    }
}
