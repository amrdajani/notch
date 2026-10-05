import SwiftUI

/// Compact spectrum bars for the collapsed island and the Media tab.
struct MusicVisualizer: View {
    var isPlaying: Bool
    var color: Color = Theme.accent
    var barCount: Int = 5
    var maxHeight: CGFloat = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying ? 0.08 : 1)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let wave = isPlaying
                        ? (sin(t * (7 + Double(index) * 0.7) + Double(index) * 1.1) + 1) / 2
                        : 0.18
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: max(2, 3 + wave * (maxHeight - 3)))
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
        .frame(height: maxHeight)
        .fixedSize()
    }
}
