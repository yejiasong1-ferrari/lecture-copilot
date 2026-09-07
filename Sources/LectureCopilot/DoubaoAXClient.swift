import AppKit
import ApplicationServices

final class DoubaoAXClient {
    func inspectTree() -> URL {
        let url = DebugLog.directory.appendingPathComponent("doubao-ax-tree.txt")
        guard let app = DoubaoWindow.runningChatApp() else {
            try? "Doubao is not running".write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        DebugLog.write("Inspect Doubao \(app.localizedName ?? "") \(app.bundleIdentifier ?? "") pid=\(app.processIdentifier)")
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var lines: [String] = [
            "name=\(app.localizedName ?? "")",
            "bundle=\(app.bundleIdentifier ?? "")",
            "pid=\(app.processIdentifier)",
            ""
        ]
        AXAccess.dump(axApp, into: &lines)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        DebugLog.write("Wrote Doubao AX tree to \(url.path) (\(lines.count) lines)")
        return url
    }
}
