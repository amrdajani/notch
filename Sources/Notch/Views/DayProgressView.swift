import SwiftUI

struct DayProgressView: View {
    // Workday window (24h clock). Kept local; simple and permission-free.
    @AppStorage("notch.day.workStart") private var workStartHour = 9
    @AppStorage("notch.day.workEnd") private var workEndHour = 17

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            ScrollView {
                VStack(spacing: 12) {
                    hero(now)
                    bar("Workday", systemImage: "briefcase",
                        progress: workdayProgress(now), detail: workdayDetail(now),
                        tint: Color(red: 0.62, green: 0.80, blue: 1.0))
                    bar("This week", systemImage: "calendar",
                        progress: weekProgress(now), detail: weekDetail(now),
                        tint: Color(red: 0.42, green: 0.86, blue: 0.58))
                    bar("This year", systemImage: "globe",
                        progress: yearProgress(now), detail: yearDetail(now),
                        tint: Color(red: 1.0, green: 0.72, blue: 0.32))
                    workdayEditor
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hero(_ now: Date) -> some View {
        let p = dayProgress(now)
        return VStack(spacing: 8) {
            Text("\(Int((p * 100).rounded()))%")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text("of today · \(timeLeftInDay(now)) left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            track(progress: p, tint: Theme.accent, height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassPanel(radius: 14)
    }

    private func bar(_ title: String, systemImage: String, progress: Double, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            track(progress: progress, tint: tint, height: 6)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .glassPanel(radius: 12)
    }

    private func track(progress: Double, tint: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }

    private var workdayEditor: some View {
        HStack {
            Text("Workday")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
            Spacer()
            Stepper("\(workStartHour):00", value: $workStartHour, in: 0...23)
                .labelsHidden()
            Text("\(workStartHour):00 – \(workEndHour):00")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
            Stepper("\(workEndHour):00", value: $workEndHour, in: 1...24)
                .labelsHidden()
        }
        .padding(10)
        .glassPanel(radius: 12)
    }

    // MARK: - Math

    private let cal = Calendar.current

    private func dayProgress(_ now: Date) -> Double {
        let start = cal.startOfDay(for: now)
        return now.timeIntervalSince(start) / 86_400
    }

    private func timeLeftInDay(_ now: Date) -> String {
        let start = cal.startOfDay(for: now)
        let left = 86_400 - now.timeIntervalSince(start)
        let h = Int(left) / 3600
        let m = (Int(left) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func workdayProgress(_ now: Date) -> Double {
        let start = cal.startOfDay(for: now)
        let s = start.addingTimeInterval(TimeInterval(workStartHour) * 3600)
        let e = start.addingTimeInterval(TimeInterval(max(workStartHour + 1, workEndHour)) * 3600)
        if now <= s { return 0 }
        if now >= e { return 1 }
        return now.timeIntervalSince(s) / e.timeIntervalSince(s)
    }

    private func workdayDetail(_ now: Date) -> String {
        let start = cal.startOfDay(for: now)
        let s = start.addingTimeInterval(TimeInterval(workStartHour) * 3600)
        let e = start.addingTimeInterval(TimeInterval(max(workStartHour + 1, workEndHour)) * 3600)
        if now < s { return "Starts in " + span(s.timeIntervalSince(now)) }
        if now >= e { return "Done for today" }
        return span(e.timeIntervalSince(now)) + " of work left"
    }

    private func weekProgress(_ now: Date) -> Double {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return now.timeIntervalSince(interval.start) / interval.duration
    }

    private func weekDetail(_ now: Date) -> String {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return "" }
        let daysLeft = Int((interval.end.timeIntervalSince(now)) / 86_400)
        return "\(daysLeft) day\(daysLeft == 1 ? "" : "s") left this week"
    }

    private func yearProgress(_ now: Date) -> Double {
        guard let interval = cal.dateInterval(of: .year, for: now) else { return 0 }
        return now.timeIntervalSince(interval.start) / interval.duration
    }

    private func yearDetail(_ now: Date) -> String {
        let day = cal.ordinality(of: .day, in: .year, for: now) ?? 0
        let total = cal.range(of: .day, in: .year, for: now)?.count ?? 365
        return "Day \(day) of \(total)"
    }

    private func span(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
