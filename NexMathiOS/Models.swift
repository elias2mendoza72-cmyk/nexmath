import Foundation

enum ChatRole {
    case user
    case assistant
}

enum ChatMode: String, CaseIterable, Identifiable {
    case solve
    case explain
    case quiz
    case exam

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var description: String {
        switch self {
        case .solve:
            return "Step-by-step solutions with verification"
        case .explain:
            return "Conceptual breakdowns with visuals"
        case .quiz:
            return "Practice problems at increasing difficulty"
        case .exam:
            return "Exam-style problems with grading"
        }
    }
}

enum ExplainStyle: String, CaseIterable, Identifiable {
    case intuition
    case equation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intuition:
            return "Intuition first"
        case .equation:
            return "Equation first"
        }
    }
}

enum ExplainAction: String {
    case deeper
    case differently
    case verify
}

enum ProgressTopic: String, CaseIterable, Identifiable {
    case limits
    case continuity
    case derivatives
    case integrals
    case applications

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var keywords: [String] {
        switch self {
        case .limits:
            return ["limit", "approach", "lhospital", "hopital"]
        case .continuity:
            return ["continuity", "continuous", "discontinuous"]
        case .derivatives:
            return ["derivative", "d/dx", "differentiation", "tangent"]
        case .integrals:
            return ["integral", "anti-derivative", "antiderivative", "area under"]
        case .applications:
            return ["optimization", "related rates", "motion", "volume", "application"]
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let mode: ChatMode
    let isHTML: Bool
    let isExplainResponse: Bool
}
