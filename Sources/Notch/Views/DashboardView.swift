import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: NotchViewModel
    var settings: SettingsStore
    var clipboard: ClipboardStore
    var capture: ScreenCaptureStore
    var lecture: LectureNotesStore
    var schedule: ScheduleStore
    var activity: ActivityStore
    var systemStats: SystemStatsStore

    var body: some View {
        VStack(spacing: 8) {
            DashboardHero(schedule: schedule)

            HStack(alignment: .top, spacing: 8) {
                calendarWidget
                todosWidget
                sessionWidget
            }
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Theme.faint)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                activityWidget
                clipWidget
                systemWidget
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var todosWidget: some View {
        widget("To-dos", symbol: "checklist") {
            let open = schedule.openReminders
            if !schedule.remindersAllowed {
                emptyState("checklist", "Sync your reminders and tasks.", actionLabel: "Allow access") {
                    Task { await schedule.requestAccess() }
                }
            } else if open.isEmpty {
                Button {
                    viewModel.select(.todos)
                } label: {
                    emptyState("checkmark.circle", "All caught up.")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 5) {
                    ForEach(open.prefix(4)) { item in
                        Button {
                            schedule.toggleReminder(item.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(item.isOverdue ? Color(red: 1.0, green: 0.40, blue: 0.44) : Theme.accent)
                                Text(item.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Open list") { viewModel.select(.todos) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var calendarWidget: some View {
        widget("Calendar", symbol: "calendar") {
            if !schedule.eventsAllowed {
                emptyState("calendar", "See what’s next on your day.", actionLabel: "Allow access") {
                    Task { await schedule.requestAccess() }
                }
            } else if let meeting = schedule.currentMeeting {
                Button {
                    viewModel.select(.calendar)
                    schedule.selectedEventID = meeting.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text("In meeting · \(ScheduleFormat.countdown(to: meeting.end)) left")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                let upcoming = schedule.todayEvents.filter { $0.end > Date() }
                if upcoming.isEmpty {
                    Button {
                        viewModel.select(.calendar)
                    } label: {
                        emptyState("calendar", "No more events today.")
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(upcoming.prefix(3)) { event in
                            Button {
                                viewModel.select(.calendar)
                                schedule.selectedEventID = event.id
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ScheduleFormat.time(event.start))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.accent)
                                    Text(event.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var sessionWidget: some View {
        widget("Session", symbol: "bolt") {
            if lecture.isRecording {
                lectureSession
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.activity.isIdle ? "Ready" : viewModel.activity.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("⌃⌥Space opens the island · ⌃⌥N saves a clip")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        viewModel.isPinned = true
                        viewModel.select(.notes)
                        Task { await lecture.toggle() }
                    } label: {
                        Text("Record lecture")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(settings.isConfigured ? Theme.accent : Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.isConfigured)
                }
            }
        }
    }

    private var lectureSession: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lecture.elapsedLabel)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            Text("Lecture")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
            Button("Stop & note") {
                Task { await lecture.toggle() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.44))
        }
    }

    private var activityWidget: some View {
        widget("Activity", symbol: "bell") {
            if activity.events.isEmpty {
                emptyState("bell.slash", "Nothing yet — actions land here.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activity.events.prefix(4)) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(event.tint)
                                .frame(width: 14)
                            Text(event.text)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(event.date, style: .relative)
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }

    private var clipWidget: some View {
        widget("Clipboard", symbol: "doc.on.clipboard") {
            if let item = clipboard.latestText {
                Button {
                    viewModel.select(.clipboard)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.preview)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text)
                            .lineLimit(4)
                            .truncationMode(isLink(item.preview) ? .middle : .tail)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            Image(systemName: isLink(item.preview) ? "link" : "text.alignleft")
                                .font(.system(size: 8, weight: .semibold))
                            Text(item.createdAt, style: .relative)
                                .monospacedDigit()
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            } else {
                emptyState("doc.on.clipboard", "Copy something and it lands here.")
            }
        }
    }

    private func isLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    private var systemWidget: some View {
        widget("System", symbol: "cpu") {
            VStack(alignment: .leading, spacing: 9) {
                statRow("CPU", value: systemStats.cpu, tint: Color(red: 0.62, green: 0.80, blue: 1.0))
                statRow("Memory", value: systemStats.memory, tint: Color(red: 0.72, green: 0.62, blue: 0.96))
                if let level = systemStats.batteryLevel {
                    batteryRow(level)
                } else {
                    statRow("Load", value: systemStats.cpu, tint: Theme.accent)
                }
            }
        }
    }

    private func statRow(_ label: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            meter(value: value, tint: tint)
        }
    }

    private func batteryRow(_ level: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: systemStats.isCharging ? "bolt.fill" : "battery.100")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(systemStats.isCharging ? Color(red: 0.42, green: 0.86, blue: 0.58) : Theme.muted)
                Text("Battery")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int((level * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            meter(value: level, tint: batteryTint(level))
        }
    }

    private func meter(value: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * min(1, max(0, value))))
                    .animation(.easeOut(duration: 0.5), value: value)
            }
        }
        .frame(height: 5)
    }

    private func batteryTint(_ level: Double) -> Color {
        if systemStats.isCharging { return Color(red: 0.42, green: 0.86, blue: 0.58) }
        if level < 0.2 { return Color(red: 1.0, green: 0.40, blue: 0.44) }
        return Theme.accent
    }

    private func widget(_ title: String, symbol: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
            content()
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.04))
                    .offset(x: 12, y: 10)
            }
        }
        .background(Theme.faint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift()
    }

    /// A centered empty/permission state with an icon and an optional CTA button.
    private func emptyState(_ symbol: String, _ text: String, actionLabel: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(Theme.muted)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.accentMuted, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
