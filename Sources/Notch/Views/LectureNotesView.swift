import SwiftUI

struct LectureNotesView: View {
    @Bindable var lecture: LectureNotesStore
    var settings: SettingsStore
    @Bindable var viewModel: NotchViewModel
    var voice: VoiceListener
    var onRequestKey: () -> Void
    var clipboardText: String = ""
    @State private var isPreviewing = false

    var body: some View {
        VStack(spacing: 8) {
            header

            if let error = lecture.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if lecture.isRecording {
                transcriptPane
            } else if lecture.isGenerating {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Writing notes from the transcript…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let note = lecture.selected {
                noteEditor(note)
            } else {
                hub
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if lecture.selected != nil, !lecture.isRecording, !lecture.isGenerating {
                Button {
                    lecture.closeEditor()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26, height: 26)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .help("All notes")
            }

            Button {
                viewModel.isPinned = true
                viewModel.select(.notes)
                if lecture.isRecording == false {
                    voice.stop()
                }
                Task { await lecture.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: lecture.isRecording ? "stop.fill" : "record.circle")
                    Text(lecture.isRecording ? "Stop & note" : "Record")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(lecture.isRecording ? Color(red: 1.0, green: 0.40, blue: 0.44) : Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                    .background(
                    (lecture.isRecording ? Color(red: 1.0, green: 0.40, blue: 0.44).opacity(0.14) : Theme.accentMuted),
                    in: Capsule()
                )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(lecture.isGenerating || (!settings.isConfigured && !lecture.isRecording))

            if lecture.isRecording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(lecture.elapsedLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
            } else if lecture.selected == nil {
                Button {
                    beginWriting()
                    lecture.createNote()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.pencil")
                        Text("New note")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accentMuted, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                if !clipboardText.isEmpty {
                    Button {
                        beginWriting()
                        lecture.createNote(body: clipboardText)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.clipboard")
                            Text("From clip")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accentMuted, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("\(GlobalHotKey.clipNoteName) also saves the current clipboard as a note")
                }
            }

            Spacer()
        }
    }

    private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Search notes", text: $lecture.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassPanel(radius: 12)
                    .onChange(of: lecture.search) {
                        if !lecture.search.isEmpty {
                            viewModel.isPinned = true
                            viewModel.isChatFocused = true
                        }
                    }

                notesSection
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)

            if lecture.notes.isEmpty {
                Text("Write a note, or record a lecture and Notch will draft it for you.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            } else if lecture.visibleNotes.isEmpty {
                Text("No notes match that search.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 4) {
                    ForEach(lecture.visibleNotes) { note in
                        Button {
                            beginWriting()
                            lecture.selectedID = note.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: note.isLecture ? "mic.fill" : "note.text")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text(noteSubtitle(note))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .glassPanel(radius: 12)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func noteEditor(_ note: LectureNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Title", text: titleBinding(note))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .onChange(of: note.notes) {
                        viewModel.isPinned = true
                    }

                Spacer(minLength: 0)

                Button {
                    isPreviewing.toggle()
                    beginWriting()
                } label: {
                    Text(isPreviewing ? "Edit" : "Preview")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accentMuted, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Add title as to-do") { lecture.addTodo(from: note.title) }
                    Button("Copy notes") { lecture.copyNotes() }
                    if note.isLecture {
                        Button("Copy transcript") { lecture.copyTranscript() }
                    }
                    Button("Show in Finder") { lecture.reveal(note) }
                    Divider()
                    Button("Delete", role: .destructive) { lecture.remove(note) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.muted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            if isPreviewing {
                ScrollView {
                    Text(markdown(note.notes))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .glassPanel(radius: 12)
            } else {
                TextEditor(text: bodyBinding(note))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .glassPanel(radius: 12)
                    .onChange(of: note.notes) {
                        viewModel.isPinned = true
                        viewModel.isChatFocused = true
                    }
            }
        }
        .onAppear {
            isPreviewing = false
            beginWriting()
        }
    }

    private var transcriptPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(lecture.liveTranscript.isEmpty ? "Listening for the lecture…" : lecture.liveTranscript)
                    .font(.system(size: 12))
                    .foregroundStyle(lecture.liveTranscript.isEmpty ? Theme.muted : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("tail")
            }
            .onChange(of: lecture.liveTranscript) {
                proxy.scrollTo("tail", anchor: .bottom)
            }
        }
    }

    private func titleBinding(_ note: LectureNote) -> Binding<String> {
        Binding(
            get: { lecture.notes.first { $0.id == note.id }?.title ?? note.title },
            set: { lecture.updateTitle(note.id, $0) }
        )
    }

    private func bodyBinding(_ note: LectureNote) -> Binding<String> {
        Binding(
            get: { lecture.notes.first { $0.id == note.id }?.notes ?? note.notes },
            set: { lecture.updateBody(note.id, $0) }
        )
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }

    private func beginWriting() {
        viewModel.isPinned = true
        viewModel.isChatFocused = true
        onRequestKey()
    }

    private func noteSubtitle(_ note: LectureNote) -> String {
        let age = relativeAge(from: note.createdAt)
        if note.isLecture {
            let minutes = max(1, Int((note.duration / 60).rounded()))
            return "Lecture · \(minutes)m · \(age)"
        }
        let preview = note.preview
        if preview.isEmpty || preview == note.title {
            return age
        }
        return "\(preview) · \(age)"
    }

    private func relativeAge(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))m ago" }
        if seconds < 86_400 { return "\(max(1, Int(seconds / 3600)))h ago" }
        return "\(max(1, Int(seconds / 86_400)))d ago"
    }
}
