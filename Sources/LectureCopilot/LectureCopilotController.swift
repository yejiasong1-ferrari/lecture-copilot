import AppKit

final class LectureCopilotController {
    var onClassModeChanged: ((Bool) -> Void)?

    private(set) var classModeEnabled = true {
        didSet { onClassModeChanged?(classModeEnabled) }
    }

    private let prompts = PromptStore()
    private let doubao = DoubaoAutomation()
    private let responseReader = DoubaoResponseReader()
    private let floatingWindow = FloatingAnswerWindow()
    private let capture = ScreenshotCapture()
    private let imageCache = CapturedImageCache(ttl: 30)

    private var previousActiveApp: PreviousActiveApp?
    private var lastShiftUpAt: Date?
    private var shiftUpSequence = 0
    private var isBusy = false
    private var pendingRead: PendingDoubaoRead?

    private struct PendingDoubaoRead {
        let prompt: String
        let action: CopilotAction
        let expiresAt: Date
    }

    private struct PreviousActiveApp {
        let bundleIdentifier: String?
        let localizedName: String?
        let bundleURL: URL?
        let processIdentifier: pid_t
        let browserContext: BrowserContext?
    }

    private struct BrowserContext {
        let bundleIdentifier: String
        let windowID: Int
        let tabIndex: Int
    }

    func toggleClassMode() {
        classModeEnabled.toggle()
    }

    func shouldHandleReturnKey() -> Bool {
        guard classModeEnabled, !isBusy, let pendingRead else { return false }
        if pendingRead.expiresAt < Date() {
            self.pendingRead = nil
            return false
        }
        return true
    }

    func handle(_ event: HotKeyEvent) {
        guard classModeEnabled else { return }
        DebugLog.write("Hotkey received: \(event)")

        switch event {
        case .shiftLeft:
            run(.translate)
        case .shiftRight:
            run(.explain)
        case .shiftUp:
            handleShiftUp()
        case .shiftDown:
            run(.backToClass)
        case .returnKey:
            retryPendingRead()
        }
    }

    func run(_ action: CopilotAction, useLastCapture: Bool = false) {
        guard !isBusy else { return }
        DebugLog.write("Run action: \(action)")

        if action == .backToClass {
            backToClass()
            return
        }

        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.perform(action, useLastCapture: useLastCapture)
            DispatchQueue.main.async {
                self?.isBusy = false
            }
        }
    }

    func inspectDoubao() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let url = self?.doubao.inspectAccessibilityTree() else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func translateLastCapture() {
        run(.translate, useLastCapture: true)
    }

    func runLastCapture(_ action: CopilotAction) {
        run(action, useLastCapture: true)
    }

    func extractPendingAnswer() {
        retryPendingRead()
    }

    func openDoubao() {
        doubao.activateDoubao()
    }

    func openPromptSettings() {
        let url = prompts.ensureSettingsFile()
        NSWorkspace.shared.open(url)
    }

    func openLastAnswer() {
        LastOutputStore.reveal()
    }

    func showShortcutSettings() {
        let alert = NSAlert()
        alert.messageText = "Lecture Copilot Shortcuts"
        alert.informativeText = """
        Class Mode ON 时可用：

        Translate: Shift + Left
        Explain: Shift + Right
        Direct Answer: Shift + Up
        Say in Class: Shift + Up, Up within 600ms
        Read Doubao Answer: Return
        Back to Class: Shift + Down
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func handleShiftUp() {
        let now = Date()
        let isDoublePress = lastShiftUpAt.map { now.timeIntervalSince($0) <= 0.6 } ?? false
        lastShiftUpAt = now

        if isDoublePress {
            shiftUpSequence += 1
            run(.sayInClass)
        } else {
            shiftUpSequence += 1
            let sequence = shiftUpSequence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { [weak self] in
                guard let self,
                      self.shiftUpSequence == sequence,
                      let lastShiftUpAt = self.lastShiftUpAt,
                      Date().timeIntervalSince(lastShiftUpAt) >= 0.6 else { return }
                self.run(.directAnswer)
            }
        }
    }

    private func perform(_ action: CopilotAction, useLastCapture: Bool = false) {
        savePreviousActiveApp()

        guard let promptKey = action.promptKey else { return }
        let prompt = prompts.prompt(for: promptKey)

        if action == .sayInClass, imageCache.restoreToPasteboardIfFresh() {
            DebugLog.write("Using fresh cached image for Say in Class")
            sendAndShowAnswer(prompt: prompt, action: action)
            return
        }

        if useLastCapture {
            DebugLog.write("Using last capture for \(action)")
            guard capture.prepareLastCapture() else {
                DispatchQueue.main.async { [weak self] in
                    self?.floatingWindow.showLoading("没有找到 last-capture.png", action: action)
                }
                return
            }
            imageCache.storeCurrentPasteboardImage()
            sendAndShowAnswer(prompt: prompt, action: action)
            return
        }

        DebugLog.write("Starting interactive screenshot")
        if !Permissions.hasScreenCapturePermission() {
            DebugLog.write("Screen capture permission is missing; requesting access")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.floatingWindow.showLoading("正在请求屏幕录制权限…", action: action)
                Permissions.requestScreenCapturePermission { [weak self] granted in
                    guard let self else { return }
                    if granted {
                        DebugLog.write("Screen capture permission granted")
                        self.floatingWindow.close()
                        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                            self?.captureAndSend(prompt: prompt, action: action)
                        }
                    } else {
                        DebugLog.write("Screen capture permission denied or not yet enabled")
                        self.floatingWindow.showLoading("还需要打开屏幕录制权限。\n\n请在系统设置的“屏幕录制与系统音频录制”中，点击 + 添加 Lecture Copilot.app 并打开开关，然后退出并重新打开 App。", action: action)
                        Permissions.showScreenCaptureAlert()
                    }
                }
            }
            return
        }

        captureAndSend(prompt: prompt, action: action)
    }

    private func captureAndSend(prompt: String, action: CopilotAction) {
        guard capture.captureSelectionToClipboard() else {
            DebugLog.write("Screenshot failed or was cancelled")
            NSSound.beep()
            DispatchQueue.main.async { [weak self] in
                self?.floatingWindow.showLoading("Screenshot was cancelled.", action: action)
            }
            return
        }

        DebugLog.write("Screenshot captured to clipboard")
        imageCache.storeCurrentPasteboardImage()
        sendAndShowAnswer(prompt: prompt, action: action)
    }

    private func sendAndShowAnswer(prompt: String, action: CopilotAction) {
        pendingRead = nil
        DispatchQueue.main.async { [weak self] in
            self?.floatingWindow.showLoading("Sending screenshot to Doubao...", action: action)
        }

        guard Permissions.hasAccessibilityPermission() else {
            DebugLog.write("Accessibility permission is missing before Doubao automation")
            DispatchQueue.main.async { [weak self] in
                self?.backToClass()
                self?.floatingWindow.showLoading("需要辅助功能权限才能操作豆包。", action: action)
                Permissions.showAutomationAlert()
            }
            return
        }

        let sendResult = doubao.sendClipboardImage(prompt: prompt, restoreFrontmost: { [weak self] in
            self?.backToClass()
        })
        guard sendResult.success else {
            DispatchQueue.main.async { [weak self] in
                self?.backToClass()
                self?.floatingWindow.showAnswer(sendResult.userMessage, action: action)
            }
            return
        }

        backToClass()
        updatePendingRead(prompt: prompt, action: action, response: nil)
        DebugLog.write("capture: sent, waiting for manual Return to extract")
        DispatchQueue.main.async { [weak self] in
            self?.floatingWindow.showLoading(
                "已发送到豆包。生成完成后按 Return 读取。",
                action: action
            )
        }

        if FileManager.default.fileExists(atPath: DebugLog.directory.appendingPathComponent("auto-extract").path) {
            DebugLog.write("capture: auto-extract flag on, waiting 20s then extracting")
            Thread.sleep(forTimeInterval: 20)
            readExistingAnswer(prompt: prompt, action: action)
        }
    }

    private func retryPendingRead() {
        guard shouldHandleReturnKey(), let pendingRead else { return }
        guard !isBusy else { return }

        isBusy = true
        DebugLog.write("Extract Doubao answer: \(pendingRead.action)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readExistingAnswer(prompt: pendingRead.prompt, action: pendingRead.action)
            DispatchQueue.main.async {
                self?.isBusy = false
            }
        }
    }

    private func readExistingAnswer(prompt: String, action: CopilotAction) {
        DispatchQueue.main.async { [weak self] in
            self?.floatingWindow.showLoading("Reading Doubao answer...", action: action)
        }

        guard Permissions.hasAccessibilityPermission() else {
            DebugLog.write("Accessibility permission is missing before Doubao retry read")
            DispatchQueue.main.async { [weak self] in
                self?.floatingWindow.showLoading("需要辅助功能权限才能读取豆包。", action: action)
                Permissions.showAutomationAlert()
            }
            return
        }

        installResponseCallbacks(prompt: prompt, action: action)
        let captured = responseReader.captureCompletedResponse(prompt: prompt, action: action, timeout: 25)
        let response = OutputQualityValidator.prepareForDisplay(captured, action: action, prompt: prompt)
        updatePendingRead(prompt: prompt, action: action, response: response)

        DispatchQueue.main.async { [weak self] in
            self?.backToClass()
            self?.floatingWindow.showAnswer(response ?? "还是没有读到完整回答。\n\n请确认豆包窗口里已经生成答案；如果答案可见但小窗读不到，说明当前豆包界面没有把正文暴露出来，需要继续适配读取逻辑。", action: action)
        }
    }

    private func installResponseCallbacks(prompt: String, action: CopilotAction) {
        responseReader.onPartialAnswer = { [weak self] text in
            DispatchQueue.main.async {
                guard let displayText = OutputQualityValidator.prepareForDisplay(text, action: action, prompt: prompt) else {
                    return
                }
                self?.floatingWindow.showAnswer(displayText, action: action)
            }
        }
        responseReader.restoreClassApp = { [weak self] in
            let restore = { self?.backToClass() }
            if Thread.isMainThread {
                restore()
            } else {
                DispatchQueue.main.sync(execute: restore)
            }
        }
    }

    private func updatePendingRead(prompt: String, action: CopilotAction, response: String?) {
        if response == nil {
            pendingRead = PendingDoubaoRead(
                prompt: prompt,
                action: action,
                expiresAt: Date().addingTimeInterval(180)
            )
        } else {
            pendingRead = nil
        }
    }

    private func savePreviousActiveApp() {
        let active = NSWorkspace.shared.frontmostApplication
        guard let active,
              active.bundleIdentifier != Bundle.main.bundleIdentifier,
              !isDoubaoApp(active) else {
            return
        }

        previousActiveApp = PreviousActiveApp(
            bundleIdentifier: active.bundleIdentifier,
            localizedName: active.localizedName,
            bundleURL: active.bundleURL,
            processIdentifier: active.processIdentifier,
            browserContext: captureBrowserContext(for: active)
        )
        DebugLog.write("Saved previous app: \(active.localizedName ?? "unknown") \(active.bundleIdentifier ?? "no-bundle-id")")
    }

    private func backToClass() {
        guard let previousActiveApp else { return }

        if let bundleURL = previousActiveApp.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                if let error {
                    DebugLog.write("Back to class openApplication failed: \(error.localizedDescription)")
                }
            }
            DebugLog.write("Requested return to previous app by URL: \(bundleURL.path)")
        }

        if let running = NSRunningApplication(processIdentifier: previousActiveApp.processIdentifier) {
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            DebugLog.write("Returned to previous app by pid: \(previousActiveApp.processIdentifier)")
        }

        if let bundleIdentifier = previousActiveApp.bundleIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                if let browserContext = previousActiveApp.browserContext,
                   self?.restoreBrowserContext(browserContext) == true {
                    DebugLog.write("Returned to previous browser window \(browserContext.windowID), tab \(browserContext.tabIndex)")
                } else if self?.activateAppWithAppleScript(bundleIdentifier: bundleIdentifier) == true {
                    DebugLog.write("Returned to previous app by bundle id: \(bundleIdentifier)")
                }
            }
        }
    }

    private func activateAppWithAppleScript(bundleIdentifier: String) -> Bool {
        let escaped = bundleIdentifier.appleScriptEscaped
        let source = """
        tell application id "\(escaped)"
            activate
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            DebugLog.write("Back to class AppleScript failed: \(error)")
            return false
        }

        return true
    }

    private func captureBrowserContext(for app: NSRunningApplication) -> BrowserContext? {
        guard let bundleIdentifier = app.bundleIdentifier,
              isSupportedBrowser(bundleIdentifier) else {
            return nil
        }

        let source = browserCaptureScript(bundleIdentifier: bundleIdentifier)
        guard let result = executeAppleScript(source),
              !result.isEmpty else {
            DebugLog.write("Browser context capture returned empty for \(bundleIdentifier)")
            return nil
        }

        let parts = result.split(separator: "|").map(String.init)
        guard parts.count == 2,
              let windowID = Int(parts[0]),
              let tabIndex = Int(parts[1]) else {
            DebugLog.write("Browser context capture could not parse: \(result)")
            return nil
        }

        DebugLog.write("Saved browser context: \(bundleIdentifier), window \(windowID), tab \(tabIndex)")
        return BrowserContext(bundleIdentifier: bundleIdentifier, windowID: windowID, tabIndex: tabIndex)
    }

    private func restoreBrowserContext(_ context: BrowserContext) -> Bool {
        let source = browserRestoreScript(
            bundleIdentifier: context.bundleIdentifier,
            windowID: context.windowID,
            tabIndex: context.tabIndex
        )
        guard let result = executeAppleScript(source) else {
            return false
        }
        return result == "ok"
    }

    private func browserCaptureScript(bundleIdentifier: String) -> String {
        let escaped = bundleIdentifier.appleScriptEscaped
        if bundleIdentifier == "com.apple.Safari" {
            return """
            tell application id "\(escaped)"
                if (count of windows) is 0 then return ""
                set winID to id of front window
                set tabIndex to index of current tab of front window
                return (winID as text) & "|" & (tabIndex as text)
            end tell
            """
        }

        return """
        tell application id "\(escaped)"
            if (count of windows) is 0 then return ""
            set winID to id of front window
            set tabIndex to active tab index of front window
            return (winID as text) & "|" & (tabIndex as text)
        end tell
        """
    }

    private func browserRestoreScript(bundleIdentifier: String, windowID: Int, tabIndex: Int) -> String {
        let escaped = bundleIdentifier.appleScriptEscaped
        if bundleIdentifier == "com.apple.Safari" {
            return """
            tell application id "\(escaped)"
                activate
                repeat with browserWindow in windows
                    if id of browserWindow is \(windowID) then
                        set index of browserWindow to 1
                        if (count of tabs of browserWindow) >= \(tabIndex) then
                            set current tab of browserWindow to tab \(tabIndex) of browserWindow
                        end if
                        return "ok"
                    end if
                end repeat
                return "missing"
            end tell
            """
        }

        return """
        tell application id "\(escaped)"
            activate
            repeat with browserWindow in windows
                if id of browserWindow is \(windowID) then
                    set index of browserWindow to 1
                    if (count of tabs of browserWindow) >= \(tabIndex) then
                        set active tab index of browserWindow to \(tabIndex)
                    end if
                    return "ok"
                end if
            end repeat
            return "missing"
        end tell
        """
    }

    private func executeAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            DebugLog.write("AppleScript failed: \(error)")
            return nil
        }
        return result?.stringValue
    }

    private func isSupportedBrowser(_ bundleIdentifier: String) -> Bool {
        [
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.apple.Safari"
        ].contains(bundleIdentifier)
    }

    private func isDoubaoApp(_ app: NSRunningApplication) -> Bool {
        let name = app.localizedName ?? ""
        return ["豆包", "Doubao", "豆包浏览器", "Doubao Browser"].contains(name)
    }
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
