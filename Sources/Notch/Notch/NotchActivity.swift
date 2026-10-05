import SwiftUI

enum NotchActivity: Equatable {
    case idle
    case listening
    case thinking
    case downloading
    case capturing
    case lecturing
    case meeting
    case done
    case copied

    var isIdle: Bool { self == .idle }

    var isLive: Bool {
        switch self {
        case .listening, .thinking, .downloading, .capturing, .lecturing, .meeting: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .idle: "Notch"
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .downloading: "Downloading…"
        case .capturing: "Capturing…"
        case .lecturing: "Lecture…"
        case .meeting: "Meeting"
        case .done: "Done"
        case .copied: "Copied"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "sparkles"
        case .listening: "mic.fill"
        case .thinking: "sparkles"
        case .downloading: "arrow.down"
        case .capturing: "camera.fill"
        case .lecturing: "mic.fill"
        case .meeting: "calendar"
        case .done: "checkmark"
        case .copied: "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .listening:
            Color(red: 1.0, green: 0.40, blue: 0.44)
        case .thinking:
            Theme.accent
        case .downloading:
            Color(red: 0.62, green: 0.80, blue: 1.0)
        case .capturing:
            Color(red: 1.0, green: 0.72, blue: 0.32)
        case .lecturing:
            Color(red: 1.0, green: 0.40, blue: 0.44)
        case .meeting:
            Theme.accent
        case .done, .copied:
            Color(red: 0.42, green: 0.86, blue: 0.58)
        case .idle:
            Theme.accent
        }
    }
}
