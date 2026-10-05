import SwiftUI

struct NowPlayingBar: View {
    var store: NowPlayingStore
    @State private var dragFraction: Double?

    var body: some View {
        Group {
            if store.isAvailable {
                player
            } else {
                emptyState
            }
        }
        .frame(maxHeight: 52)
        .clipped()
    }

    private var player: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(store.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if !store.artist.isEmpty {
                        Text(store.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    MusicVisualizer(isPlaying: store.isPlaying, maxHeight: 10)
                }
                scrubber
            }
            transport
        }
        .frame(height: 48)
    }

    private var artwork: some View {
        Group {
            if let art = store.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.accentMuted
                    Image(systemName: "music.note")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var scrubber: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let fraction = dragFraction ?? store.progress
            HStack(spacing: 6) {
                Text(Self.time(store.duration * fraction))
                    .frame(width: 28, alignment: .leading)
                Color.clear
                    .frame(height: 4)
                    .overlay {
                        GeometryReader { geo in
                            let width = geo.size.width
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.14))
                                Capsule().fill(Theme.accent).frame(width: max(0, width * fraction))
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        dragFraction = min(1, max(0, value.location.x / max(width, 1)))
                                    }
                                    .onEnded { value in
                                        store.seek(toFraction: min(1, max(0, value.location.x / max(width, 1))))
                                        dragFraction = nil
                                    }
                            )
                        }
                    }
                Text("-" + Self.time(max(0, store.duration * (1 - fraction))))
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    private var transport: some View {
        HStack(spacing: 2) {
            toggleButton("shuffle", on: store.shuffleOn) { store.toggleShuffle() }
            controlButton("backward.fill", size: 11) { store.previous() }
            Button { store.playPause() } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.surface)
                    .frame(width: 28, height: 28)
                    .background(Theme.text, in: Circle())
            }
            .buttonStyle(.plain)
            controlButton("forward.fill", size: 11) { store.next() }
            toggleButton(store.repeatMode == 2 ? "repeat.1" : "repeat", on: store.repeatMode != 0) { store.cycleRepeat() }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func toggleButton(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Theme.muted)
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            MusicVisualizer(isPlaying: false, maxHeight: 10)
            Text(store.errorMessage == nil ? "Nothing playing" : "Can’t read player")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            if store.canRequestAccess {
                Button("Allow") { store.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
    }

    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
