import Foundation

final class ClassSessionStore {
    private static let recordTranslateKey = "classSession.recordTranslate"

    var recordTranslate: Bool {
        get { UserDefaults.standard.bool(forKey: Self.recordTranslateKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.recordTranslateKey) }
    }

    private(set) var session: ClassSession?

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var notesRoot: URL {
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lecture Copilot", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func shouldRecord(_ action: CopilotAction) -> Bool {
        switch action {
        case .explain, .directAnswer, .sayInClass:
            return true
        case .translate:
            return recordTranslate
        case .backToClass, .classSummary:
            return false
        }
    }

    func start() -> ClassSession {
        let session = ClassSession(
            id: UUID(),
            title: "Class Session",
            startTime: Date(),
            endTime: nil,
            interactions: [],
            summary: nil,
            savePath: nil
        )
        self.session = session
        persist()
        DebugLog.write("Class session started \(session.id)")
        return session
    }

    func end() -> ClassSession? {
        guard var session else { return nil }
        session.endTime = session.endTime ?? Date()
        self.session = session
        persist()
        DebugLog.write("Class session ended \(session.id), \(session.recordedCount) notes")
        return session
    }

    func beginInteraction(action: CopilotAction) -> UUID? {
        guard shouldRecord(action), var session, session.endTime == nil else { return nil }

        let id = UUID()
        var relativePath: String?
        let source = DoubaoWindow.lastCaptureURL
        if fileManager.fileExists(atPath: source.path) {
            let relative = "shots/\(id.uuidString).png"
            let destination = folder(for: session.id).appendingPathComponent(relative)
            try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(at: source, to: destination)
            relativePath = relative
        }

        session.interactions.append(
            ClassInteraction(
                id: id,
                timestamp: Date(),
                mode: action.displayName,
                screenshotRelativePath: relativePath,
                prompt: action.displayName,
                answer: ""
            )
        )
        self.session = session
        persist()
        return id
    }

    func finishInteraction(id: UUID, answer: String) {
        guard var session else { return }
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("Still generating") else { return }
        guard let index = session.interactions.firstIndex(where: { $0.id == id }) else { return }
        session.interactions[index].answer = cleaned
        self.session = session
        persist()
    }

    func setSummary(_ summary: String) {
        guard var session else { return }
        session.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        persist()
    }

    func markSaved(at url: URL) {
        guard var session else { return }
        session.savePath = url.path
        session.title = url.deletingPathExtension().lastPathComponent
        self.session = session
        persist()
    }

    func clear() {
        session = nil
        DebugLog.write("Class session cleared")
    }

    func snapshot() -> ClassHUDSnapshot {
        guard let session else { return .idle }
        let phase: ClassHUDSnapshot.Phase
        if session.savePath != nil {
            phase = .saved
        } else if session.summary?.isEmpty == false, session.endTime != nil {
            phase = .summaryReady
        } else if session.endTime != nil {
            phase = .summarizing
        } else {
            phase = .running
        }
        return ClassHUDSnapshot(
            phase: phase,
            elapsed: session.duration,
            interactionCount: session.recordedCount,
            title: session.title,
            startClock: ClassHUDSnapshot.clockText(session.startTime)
        )
    }

    func doubaoPayload() -> String {
        guard let session else { return "No class session." }
        let duration = ClassHUDSnapshot.durationText(session.duration)
        let notes = session.interactions.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if notes.isEmpty {
            return """
            Class Session
            Start: \(ClassHUDSnapshot.clockText(session.startTime))
            Duration: \(duration)

            No Explain / Direct Answer / Say in Class notes were saved this class.
            """
        }

        var counts: [String: Int] = [:]
        for note in notes {
            counts[note.mode, default: 0] += 1
        }
        let countLine = ["Explain", "Direct Answer", "Say in Class", "Translate"]
            .compactMap { mode -> String? in
                guard let value = counts[mode], value > 0 else { return nil }
                return "\(mode): \(value)"
            }
            .joined(separator: " · ")

        var body = """
        Class Session
        Start: \(ClassHUDSnapshot.clockText(session.startTime))
        Duration: \(duration)
        \(countLine)

        """
        for note in notes {
            body += """

            [\(Self.timeFormatter.string(from: note.timestamp))] \(note.mode)

            \(note.answer)

            """
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func writeNote(to url: URL) throws {
        guard let session else { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let shotsFolder = url.deletingPathExtension().appendingPathComponent("shots", isDirectory: true)
        if fileManager.fileExists(atPath: shotsFolder.path) {
            try fileManager.removeItem(at: shotsFolder)
        }

        try markdown(named: url.deletingPathExtension().lastPathComponent, copyShotsTo: shotsFolder)
            .write(to: url, atomically: true, encoding: .utf8)
        markSaved(at: url)
    }

    func writePreviewMarkdown() -> URL? {
        guard session != nil else { return nil }
        let url = DebugLog.directory.appendingPathComponent("class-summary-preview.md")
        let markdown = markdown(named: session?.title ?? "Class Session", copyShotsTo: nil)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func markdown(named title: String, copyShotsTo shotsFolder: URL?) -> String {
        guard let session else { return "" }
        var text = """
        # \(title)

        - Start: \(ClassHUDSnapshot.clockText(session.startTime))
        - End: \(ClassHUDSnapshot.clockText(session.endTime ?? Date()))
        - Duration: \(ClassHUDSnapshot.durationText(session.duration))
        - Notes: \(session.recordedCount)

        """

        if let summary = session.summary, !summary.isEmpty {
            text += "\n\(summary)\n"
        }

        let notes = session.interactions.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !notes.isEmpty {
            text += "\n---\n\n## Class Record\n"
            for note in notes {
                text += "\n### [\(Self.timeFormatter.string(from: note.timestamp))] \(note.mode)\n\n"
                if let relative = note.screenshotRelativePath {
                    let source = folder(for: session.id).appendingPathComponent(relative)
                    if fileManager.fileExists(atPath: source.path) {
                        if let shotsFolder {
                            try? fileManager.createDirectory(at: shotsFolder, withIntermediateDirectories: true)
                            let filename = source.lastPathComponent
                            let destination = shotsFolder.appendingPathComponent(filename)
                            try? fileManager.removeItem(at: destination)
                            try? fileManager.copyItem(at: source, to: destination)
                            text += "![slide](shots/\(filename))\n\n"
                        }
                    }
                }
                text += "\(note.answer)\n"
            }
        }
        return text
    }

    func defaultSaveURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let name = "Class \(formatter.string(from: session?.startTime ?? Date())).md"
        return notesRoot.appendingPathComponent(name)
    }

    private func persist() {
        guard let session else { return }
        let url = folder(for: session.id).appendingPathComponent("session.json")
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func folder(for id: UUID) -> URL {
        DebugLog.directory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
