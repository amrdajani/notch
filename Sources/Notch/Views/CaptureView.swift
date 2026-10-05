import SwiftUI

struct CaptureView: View {
    var store: ScreenCaptureStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                modeButton("Screen", symbol: "rectangle.dashed", mode: .display)
                modeButton("Selection", symbol: "selection.pin.in.out", mode: .selection)
                modeButton("Window", symbol: "macwindow", mode: .window)
            }
            .disabled(store.isCapturing)

            if store.isCapturing {
                Text("Capturing… the island is hidden so it stays out of the shot.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.85))
                    Spacer(minLength: 0)
                    Button("Settings") { store.openPrivacySettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            if let image = store.lastImage {
                preview(image)
                if store.recent.count > 1 {
                    recentStrip
                }
            } else if !store.isCapturing {
                VStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.muted)
                    Text("Capture here, or use ⌘⇧3 / ⌘⇧4. System screenshots show up in this tab too.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
    }

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.recent) { shot in
                    Button {
                        store.lastImage = shot.image
                        store.lastFileURL = shot.fileURL
                    } label: {
                        Image(nsImage: shot.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(
                                        shot.fileURL == store.lastFileURL && shot.image === store.lastImage
                                            ? Theme.accent
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func modeButton(_ title: String, symbol: String, mode: CaptureMode) -> some View {
        Button {
            Task { await store.capture(mode) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassPanel(radius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func preview(_ image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button("Copy") { store.copyLast() }
                if store.lastFileURL != nil {
                    Button("Show in Finder") { store.revealLast() }
                }
                Spacer()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(8)
        .glassPanel(radius: 14)
    }
}
