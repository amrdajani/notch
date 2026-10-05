import AppKit
import SwiftUI

/// The dashboard centerpiece: an ambient, time-of-day header with a live clock,
/// a personalized greeting, and a single smart line summarizing the day.
struct DashboardHero: View {
    var schedule: ScheduleStore

    @State private var drift = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ZStack {
                background(now)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(greeting(now))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(dateLine(now))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        summaryLine
                            .padding(.top, 3)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Capsule()
                                .fill(.white.opacity(0.25))
                                .frame(width: 56, height: 3)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(.white)
                                        .frame(width: 56 * dayFraction(now), height: 3)
                                }
                            Text(now, format: .dateTime.second(.twoDigits))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    // MARK: - Background

    private func background(_ now: Date) -> some View {
        let palette = Palette.forHour(Calendar.current.component(.hour, from: now))
        return ZStack {
            LinearGradient(colors: palette.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            // A soft light source that slowly drifts for a living, ambient feel.
            Circle()
                .fill(palette.glow)
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: drift ? 90 : -70, y: drift ? -50 : -20)
                .opacity(0.7)
        }
    }

    // MARK: - Smart summary

    @ViewBuilder
    private var summaryLine: some View {
        let info = summary
        HStack(spacing: 5) {
            Image(systemName: info.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(info.text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.16), in: Capsule())
    }

    private var summary: (symbol: String, text: String) {
        if let meeting = schedule.currentMeeting {
            return ("calendar", "In \(meeting.title) · \(ScheduleFormat.countdown(to: meeting.end)) left")
        }
        if let next = schedule.nextEvent, next.start.timeIntervalSinceNow < 4 * 3600 {
            return ("calendar", "Next: \(next.title) at \(ScheduleFormat.time(next.start))")
        }
        let overdue = schedule.overdueReminders.count
        if overdue > 0 {
            return ("exclamationmark.circle", "\(overdue) task\(overdue == 1 ? "" : "s") overdue")
        }
        let open = schedule.openReminders.count
        if open > 0 {
            return ("checklist", "\(open) task\(open == 1 ? "" : "s") on your list")
        }
        return ("sparkles", "You're all clear")
    }

    // MARK: - Text

    private func greeting(_ now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Good night"
        }
        if let name = Self.firstName {
            return "\(part), \(name)"
        }
        return part
    }

    private func dateLine(_ now: Date) -> String {
        now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Fraction of the current day elapsed (0…1).
    private func dayFraction(_ now: Date) -> Double {
        let start = Calendar.current.startOfDay(for: now)
        return min(1, max(0, now.timeIntervalSince(start) / 86_400))
    }

    /// First name from the macOS account (local, never the email).
    private static let firstName: String? = {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        guard let first = full.split(separator: " ").first, first.count > 1 else { return nil }
        return String(first)
    }()

    private struct Palette {
        var gradient: [Color]
        var glow: Color

        static func forHour(_ hour: Int) -> Palette {
            switch hour {
            case 5..<8: // dawn
                Palette(gradient: [c(0.98, 0.55, 0.45), c(0.55, 0.42, 0.72)], glow: c(1.0, 0.82, 0.55))
            case 8..<17: // day
                Palette(gradient: [c(0.26, 0.55, 0.90), c(0.40, 0.74, 0.92)], glow: c(0.85, 0.95, 1.0))
            case 17..<20: // dusk
                Palette(gradient: [c(0.96, 0.48, 0.35), c(0.42, 0.30, 0.62)], glow: c(1.0, 0.70, 0.42))
            default: // night
                Palette(gradient: [c(0.10, 0.13, 0.30), c(0.20, 0.16, 0.38)], glow: c(0.45, 0.55, 0.95))
            }
        }

        private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r, green: g, blue: b)
        }
    }
}
