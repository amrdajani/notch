import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    var createdAt: Date
}

struct LectureNote: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var transcript: String
    var notes: String
    var createdAt: Date
    var duration: TimeInterval

    var isLecture: Bool { duration > 0 || !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var preview: String {
        let line = notes.split(whereSeparator: \.isNewline).first.map(String.init) ?? title
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    }
}
