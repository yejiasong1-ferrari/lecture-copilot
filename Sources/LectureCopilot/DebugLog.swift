import Foundation

enum DebugLog {
    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lecture Copilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }()

    private static var fileURL: URL {
        directory.appendingPathComponent("debug.log")
    }

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    static var url: URL {
        fileURL
    }
}

struct JobLog {
    let id: String

    init(_ jobID: UUID) {
        id = String(jobID.uuidString.prefix(4)).uppercased()
    }

    func state(_ name: String, _ result: String, extra: String = "", elapsed: TimeInterval? = nil) {
        var line = "[job \(id)] STATE \(name) → \(result)"
        if !extra.isEmpty {
            line += " \(extra)"
        }
        if let elapsed {
            line += String(format: " %.0fms", elapsed * 1000)
        }
        DebugLog.write(line)
    }

    func done(elapsed: TimeInterval) {
        DebugLog.write(String(format: "[job %@] DONE total=%.1fs", id, elapsed))
    }
}
