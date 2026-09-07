import Foundation

enum CopilotAction {
    case translate
    case explain
    case directAnswer
    case sayInClass
    case backToClass

    var promptKey: String? {
        switch self {
        case .translate: "translate"
        case .explain: "explain"
        case .directAnswer: "directAnswer"
        case .sayInClass: "sayInClass"
        case .backToClass: nil
        }
    }

    var displayName: String {
        switch self {
        case .translate: "Translate"
        case .explain: "Explain"
        case .directAnswer: "Direct Answer"
        case .sayInClass: "Say in Class"
        case .backToClass: "Back to Class"
        }
    }

    var chipTitle: String {
        switch self {
        case .translate: "Translate"
        case .explain: "Explain"
        case .directAnswer: "Answer"
        case .sayInClass: "Speak"
        case .backToClass: "Class"
        }
    }
}

enum HotKeyEvent {
    case shiftLeft
    case shiftRight
    case shiftUp
    case shiftDown
    case returnKey
}
