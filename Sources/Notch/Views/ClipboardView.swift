import SwiftUI

struct ClipboardView: View {
    var store: ClipboardStore
    @Bindable var ai: ClipboardAIStore
    var settings: SettingsStore
    @Bindable var viewModel: NotchViewModel

    @State private var query = ""

    var body: some View {
        VStack(spacing: 8) {
            searchBar

            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if query.isEmpty, let latest = store.latestText {
                            latestCard(latest)
                        }

                        if !pinnedItems.isEmpty {
                            sectionLabel("Pinned", systemImage: "pin.fill")
                            ForEach(pinnedItems) { row($0) }
                        }

                        if !recentItems.isEmpty {
                            if !pinnedItems.isEmpty {
                                sectionLabel("Recent", systemImage: "clock")
                            }
                            ForEach(recentItems) { row($0) }
                        }

                        if pinnedItems.isEmpty, recentItems.isEmpty, query.isEmpty == false {
                            Text("No clips match “\(query)”.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 16)
                        }
                    }
                }
            }
        }
        .onChange(of: store.lastUserCaptureID) {
            ai.prepareForCapture(store.latestText)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                TextField("Search clips", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassPanel(radius: 8)

            if !store.items.isEmpty {
                Button("Clear") { store.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
            Spacer()
        }
        .foregroundStyle(Theme.muted)
        .padding(.top, 2)
    }

    private var pinnedItems: [ClipboardEntry] {
        store.pinnedItems.filter { store.matches($0, query: query) }
    }

    private var recentItems: [ClipboardEntry] {
        let latestID = query.isEmpty ? store.latestText?.id : nil
        return store.items.filter { item in
            !store.isPinned(item)
                && item.id != latestID
                && store.matches(item, query: query)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clipboard")
                .font(.system(size: 18))
                .foregroundStyle(Theme.muted)
            Text("Copy text and it shows up here with AI actions.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func latestCard(_ item: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.copy(item)
            } label: {
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !settings.isConfigured {
                Text("Add an API key in Settings to use Clipboard AI.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }

            actionGrid(for: item)

            if let error = ai.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
            }

            if ai.runningAction != nil {
                HStack {
                    Text("Writing…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Stop") { ai.stop() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.44))
                        .islandTappable()
                }
            }

            if let result = ai.result, let action = ai.resultAction {
                resultCard(result, action: action)
            }
        }
        .padding(8)
        .glassPanel(radius: 14)
    }

    private func actionGrid(for item: ClipboardEntry) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(ClipboardAction.allCases.prefix(3))) { action in
                    actionChip(action, item: item)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(ClipboardAction.allCases.suffix(3))) { action in
                    actionChip(action, item: item)
                }
            }
        }
    }

    private func actionChip(_ action: ClipboardAction, item: ClipboardEntry) -> some View {
        let active = ai.runningAction == action
        return Button {
            viewModel.isPinned = true
            Task { ai.run(action, on: item) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.symbol)
                Text(action.title)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(active ? Theme.surface : Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Theme.accent : Theme.accentMuted)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(ai.isRunning)
    }

    private func resultCard(_ result: String, action: ClipboardAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button {
                    store.copyText(result)
                    ai.markResultCopied()
                } label: {
                    Text(ai.copiedResult ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            Text(result)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .glassPanel(radius: 12)
    }

    private func thumbnail(for item: ClipboardEntry) -> some View {
        Group {
            if item.kind == .image, let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.muted.opacity(0.25), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accentMuted)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: item.kind == .image ? "photo" : "doc.on.clipboard")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                    )
            }
        }
        .frame(width: 32, height: 32)
    }

    private func row(_ item: ClipboardEntry) -> some View {
        Button {
            store.copy(item)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                thumbnail(for: item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(item.createdAt, style: .time)
                        if item.kind == .image, let size = item.image?.size {
                            Text("· \(Int(size.width))×\(Int(size.height))")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if store.lastCopiedID == item.id {
                    Text("Copied")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Button {
                    store.togglePin(item)
                } label: {
                    Image(systemName: store.isPinned(item) ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(store.isPinned(item) ? Theme.accent : Theme.muted)
                        .rotationEffect(.degrees(store.isPinned(item) ? 0 : 45))
                }
                .buttonStyle(.plain)
                .help(store.isPinned(item) ? "Unpin" : "Pin")
            }
            .padding(8)
            .glassPanel(radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(store.isPinned(item) ? "Unpin" : "Pin") { store.togglePin(item) }
            if item.kind == .text {
                Divider()
                ForEach(ClipboardAction.allCases) { action in
                    Button(action.title) {
                        viewModel.isPinned = true
                        viewModel.select(.clipboard)
                        ai.run(action, on: item)
                    }
                }
            }
            Divider()
            Button("Copy") { store.copy(item) }
            Button("Remove", role: .destructive) { store.remove(item) }
        }
    }
}
