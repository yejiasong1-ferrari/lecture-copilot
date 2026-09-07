import AppKit

enum LastOutputStore {
    static var directory: URL {
        DebugLog.directory
    }

    static var textURL: URL {
        directory.appendingPathComponent("last-answer.txt")
    }

    static var imageURL: URL {
        directory.appendingPathComponent("last-answer.png")
    }

    static func save(kind: String, action: CopilotAction?, title: String, text: String, panel: NSPanel?) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let actionName = action?.displayName ?? "none"
        let body = """
        updated: \(timestamp)
        kind: \(kind)
        action: \(actionName)
        title: \(title)

        \(text)
        """

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? body.write(to: textURL, atomically: true, encoding: .utf8)
        DebugLog.write("Floating window saved (\(kind), \(actionName), \(text.count) chars)\n--- FLOAT BEGIN ---\n\(text)\n--- FLOAT END ---")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            saveSnapshot(panel: panel)
        }
    }

    static func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([textURL])
    }

    private static func saveSnapshot(panel: NSPanel?) {
        guard let panel, let view = panel.contentView else { return }

        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }

        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: imageURL, options: .atomic)
    }
}
