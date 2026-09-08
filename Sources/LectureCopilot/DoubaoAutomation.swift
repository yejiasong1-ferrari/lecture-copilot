import AppKit

final class DoubaoAutomation {
    private let chatAppNames = ["豆包", "Doubao"]
    private let browserAppNames = ["豆包浏览器", "Doubao Browser"]

    func activateDoubao() {
        if let running = runningChatApp() {
            DebugLog.write("Activating running Doubao chat app: \(running.localizedName ?? "unknown")")
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        if let running = runningBrowserApp() {
            DebugLog.write("Activating running Doubao browser: \(running.localizedName ?? "unknown")")
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        for appName in chatAppNames {
            if NSWorkspace.shared.launchApplication(appName) {
                DebugLog.write("Launched Doubao by name: \(appName)")
                return
            }
        }

        let url = URL(fileURLWithPath: "/Applications/Doubao.app")
        DebugLog.write("Opening Doubao at \(url.path)")
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func sendClipboardImage(prompt: String, restoreFrontmost: (() -> Void)? = nil) -> DoubaoUploadResult {
        DebugLog.write("Sending clipboard image to Doubao")
        return DoubaoUploadFSM().run(
            prompt: prompt,
            imageURL: DoubaoWindow.lastCaptureURL,
            restoreFrontmost: restoreFrontmost
        )
    }

    @discardableResult
    func sendText(_ text: String, restoreFrontmost: (() -> Void)? = nil) -> DoubaoUploadResult {
        DebugLog.write("Sending class notes text to Doubao")
        return DoubaoUploadFSM().run(
            prompt: text,
            imageURL: nil,
            restoreFrontmost: restoreFrontmost
        )
    }

    func inspectAccessibilityTree() -> URL {
        DoubaoAXClient().inspectTree()
    }

    private func runningChatApp() -> NSRunningApplication? {
        appsNamed(chatAppNames).first
    }

    private func runningBrowserApp() -> NSRunningApplication? {
        appsNamed(browserAppNames).first
    }

    private func appsNamed(_ names: [String]) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            names.contains(app.localizedName ?? "")
        }
    }
}
