import Foundation

struct ClassSession: Codable {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var interactions: [ClassInteraction]
    var summary: String?
    var savePath: String?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var recordedCount: Int {
        interactions.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
}

struct ClassInteraction: Codable {
    var id: UUID
    var timestamp: Date
    var mode: String
    var screenshotRelativePath: String?
    var prompt: String
    var answer: String
}

struct ClassHUDSnapshot: Equatable {
    enum Phase: Equatable {
        case idle
        case running
        case summarizing
        case summaryReady
        case saved
    }

    var phase: Phase
    var elapsed: TimeInterval
    var interactionCount: Int
    var title: String
    var startClock: String

    static let idle = ClassHUDSnapshot(
        phase: .idle,
        elapsed: 0,
        interactionCount: 0,
        title: "Class Session",
        startClock: ""
    )

    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
