import SwiftUI

struct LiveAccessory: View {
    let activity: NotchActivity

    var body: some View {
        Group {
            switch activity {
            case .listening, .lecturing:
                PulseBars(color: activity.tint)
            case .thinking:
                ThinkingDots(color: activity.tint)
            case .downloading:
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            case .capturing:
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            case .meeting:
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(activity.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
            case .done, .copied:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(activity.tint)
            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 18)
    }
}

private struct PulseBars: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let wave = (sin(t * 8 + Double(index) * 0.9) + 1) / 2
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 4 + wave * 8)
                }
            }
        }
    }
}

private struct ThinkingDots: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.28)) { timeline in
            let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.28) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color.opacity(step == index ? 1 : 0.28))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }
}
