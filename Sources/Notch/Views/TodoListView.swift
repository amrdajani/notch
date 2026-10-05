import SwiftUI

struct TodoListView: View {
    @Bindable var schedule: ScheduleStore
    @Bindable var viewModel: NotchViewModel
    var onRequestKey: () -> Void
    @State private var showingDone = false

    var body: some View {
        Group {
            if !schedule.remindersAllowed {
                permission
            } else {
                switch schedule.todoPane {
                case .list:
                    list
                case .detail(let id):
                    if let item = schedule.reminder(id: id) {
                        detail(item)
                    } else {
                        list
                    }
                case .compose:
                    composer
                case .trash:
                    trash
                }
            }
        }
        .onAppear {
            viewModel.isPinned = true
            onRequestKey()
        }
    }

    private var permission: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
            Text("Allow Reminders so to-dos stay in sync with macOS.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Allow Reminders") {
                Task { await schedule.requestAccess() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search to-dos", text: $schedule.todoSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassPanel(radius: 12)
                    .onChange(of: schedule.todoSearch) {
                        if !schedule.todoSearch.isEmpty {
                            viewModel.isPinned = true
                            viewModel.isChatFocused = true
                        }
                    }

                Button {
                    showingDone.toggle()
                } label: {
                    Text(showingDone ? "Open" : "Done")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .glassPanel(radius: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    schedule.todoPane = .trash
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 28, height: 28)
                            .background(Theme.faint, in: Circle())
                        if !schedule.trash.isEmpty {
                            Text("\(schedule.trash.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.surface)
                                .padding(3)
                                .background(Theme.accent, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                    .islandTappable()
                }
                .buttonStyle(.plain)
                .help("Trash")

                Button {
                    viewModel.isPinned = true
                    onRequestKey()
                    schedule.beginCompose()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentMuted, in: Circle())
                        .islandTappable()
                }
                .buttonStyle(.plain)
                .help("New task")
            }

            let rows = showingDone ? schedule.visibleDone : schedule.visibleTodos
            if rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.muted)
                    Text(showingDone ? "No completed reminders" : "No reminders")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(showingDone ? "Completed tasks from Reminders show up here." : "Add a task. It stays in sync with macOS Reminders.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(rows) { item in
                            row(item)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(spacing: 8) {
            Button {
                schedule.toggleReminder(item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Theme.accent : (item.isOverdue ? Color(red: 1.0, green: 0.40, blue: 0.44) : Theme.muted))
                    .islandTappable()
            }
            .buttonStyle(.plain)

            Button {
                schedule.todoPane = .detail(item.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.isCompleted ? Theme.muted : Theme.text)
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(rowSubtitle(item))
                        .font(.system(size: 10))
                        .foregroundStyle(item.isOverdue && !item.isCompleted ? Color(red: 1.0, green: 0.40, blue: 0.44) : Theme.muted)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                schedule.deleteReminder(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .islandTappable()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .glassPanel(radius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rowSubtitle(_ item: ReminderItem) -> String {
        var parts: [String] = []
        if let due = item.dueDate {
            parts.append(ScheduleFormat.longStamp.string(from: due))
        } else {
            parts.append("No date")
        }
        parts.append(item.calendarName)
        return parts.joined(separator: " · ")
    }

    private func detail(_ item: ReminderItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    schedule.todoPane = .list
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .islandTappable()
                }
                .buttonStyle(.plain)

                Button {
                    schedule.beginEdit(item.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .islandTappable()
                }
                .buttonStyle(.plain)

                Spacer()

                Text(ScheduleFormat.dayStamp.string(from: item.dueDate ?? Date()))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 8) {
                Button {
                    schedule.toggleReminder(item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Theme.accent : Theme.muted)
                        .islandTappable()
                }
                .buttonStyle(.plain)

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .strikethrough(item.isCompleted)
            }

            ScrollView {
                VStack(spacing: 8) {
                    meta("clock", "DUE DATE", item.dueDate.map { ScheduleFormat.longStamp.string(from: $0) } ?? "No due date")
                    meta("bell", "REMINDER", item.alarmDate.map { ScheduleFormat.longStamp.string(from: $0) } ?? "No reminder")
                    meta("calendar", "SCHEDULE", scheduleLabel(item))
                    meta("note.text", "NOTES", item.notes.isEmpty ? "No notes" : item.notes)
                }
            }

            HStack {
                Button("Move to trash") {
                    schedule.deleteReminder(item.id)
                    schedule.todoPane = .list
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.44))

                Spacer()

                Button("Open Reminders") {
                    schedule.openRemindersApp()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func scheduleLabel(_ item: ReminderItem) -> String {
        if let start = item.startDate, let due = item.dueDate {
            return "\(ScheduleFormat.longStamp.string(from: start)) – \(ScheduleFormat.time(due))"
        }
        if let start = item.startDate {
            return "Starts \(ScheduleFormat.longStamp.string(from: start))"
        }
        return "No start & end"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Cancel") {
                    schedule.todoPane = schedule.draft.editingID.map(TodoPane.detail) ?? .list
                    schedule.draft = ReminderDraft()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)

                Spacer()
                Text(schedule.draft.editingID == nil ? "New Task" : "Edit Task")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()

                Button("Save") {
                    schedule.saveDraft()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(schedule.draft.canSave ? Theme.accent : Theme.muted)
                .disabled(!schedule.draft.canSave)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TITLE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                TextField("Task title", text: $schedule.draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .onChange(of: schedule.draft.title) {
                        viewModel.isPinned = true
                        viewModel.isChatFocused = true
                    }
            }

            fieldRow("clock", "DUE DATE") {
                if schedule.draft.hasDue {
                    DatePicker("", selection: $schedule.draft.due, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .tint(Theme.accent)
                } else {
                    Button("Set due date") {
                        schedule.draft.hasDue = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }

            fieldRow("calendar", "START & END") {
                if schedule.draft.hasSchedule {
                    VStack(alignment: .leading, spacing: 4) {
                        DatePicker("Start", selection: $schedule.draft.start, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .tint(Theme.accent)
                            .font(.system(size: 11))
                        DatePicker("End", selection: $schedule.draft.end, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .tint(Theme.accent)
                            .font(.system(size: 11))
                    }
                } else {
                    Button("Add start & end times") {
                        schedule.draft.hasSchedule = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }

            fieldRow("note.text", "NOTES") {
                TextField("Notes", text: $schedule.draft.notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3...6)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            viewModel.isPinned = true
            viewModel.isChatFocused = true
            onRequestKey()
        }
    }

    private var trash: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    schedule.todoPane = .list
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .islandTappable()
                }
                .buttonStyle(.plain)
                Text("Trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Kept 30 days")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if !schedule.trash.isEmpty {
                    Button("Empty") {
                        schedule.purgeTrash()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.44))
                }
            }

            if schedule.trash.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.muted)
                    Text("Trash is empty.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Text("Deleted reminders can be restored for 30 days.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(schedule.trash) { item in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text("Restore within \(ScheduleFormat.remaining(item.retainUntil.timeIntervalSinceNow))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                                Button("Restore") {
                                    schedule.restore(item)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .glassPanel(radius: 12)
                        }
                    }
                }
            }
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

    private func fieldRow<Content: View>(_ symbol: String, _ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .glassPanel(radius: 12)
    }
}
