import Foundation

enum ClipboardAction: String, CaseIterable, Identifiable {
    case explain
    case rewrite
    case summarize
    case translate
    case fixGrammar
    case generateCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: "Explain"
        case .rewrite: "Rewrite"
        case .summarize: "Summarize"
        case .translate: "Translate"
        case .fixGrammar: "Fix grammar"
        case .generateCode: "Code"
        }
    }

    var symbol: String {
        switch self {
        case .explain: "text.magnifyingglass"
        case .rewrite: "pencil.line"
        case .summarize: "list.bullet"
        case .translate: "globe"
        case .fixGrammar: "checkmark.circle"
        case .generateCode: "chevron.left.forwardslash.chevron.right"
        }
    }

    func systemPrompt(translateTo: String) -> String {
        switch self {
        case .explain:
            "Explain the following text clearly and briefly. Assume a smart reader. Short paragraphs or bullets. No preamble."
        case .rewrite:
            "Rewrite the following text so it is clearer and tighter. Keep the meaning and voice. Return only the rewrite."
        case .summarize:
            "Summarize the following text in a few short bullets. No preamble."
        case .translate:
            "Translate the following text into \(translateTo). If it is already in that language, say so in one line and return a polished version. Return only the translation."
        case .fixGrammar:
            "Fix grammar, spelling, and punctuation. Keep the original tone and meaning. Return only the corrected text."
        case .generateCode:
            "Write code that implements or matches the following request or snippet. If the language is unclear, pick the most likely one and name it in one line, then the code. Be concise."
        }
    }
}
