import AppKit
import UniformTypeIdentifiers

final class LectureCopilotController {
    var onClassModeChanged: ((Bool) -> Void)?
    var onPendingReadChanged: ((Bool) -> Void)?
    var onSessionChanged: (() -> Void)?

    private(set) var classModeEnabled = true {
        didSet { onClassModeChanged?(classModeEnabled) }
    }

    var isSessionRunning: Bool {
        sessionStore.session != nil && sessionStore.session?.endTime == nil
    }

    var recordTranslateEnabled: Bool {
        sessionStore.recordTranslate
    }

    var sessionNoteCount: Int {
        sessionStore.session?.recordedCount ?? 0
    }

    private let prompts = PromptStore()
    private let doubao = DoubaoAutomation()
    private let responseReader = DoubaoResponseReader()
    private let floatingWindow = FloatingAnswerWindow()
    private let capture = ScreenshotCapture()
    private let imageCache = CapturedImageCache(ttl: 30)
    private let sessionStore = ClassSessionStore()

    private var previousActiveApp: PreviousActiveApp?
    private var lastShiftUpAt: Date?
    private var shiftUpSequence = 0
    private var isBusy = false
    private var sessionTimer: Timer?
    private var pendingInteractionID: UUID?
    private var lastExtractAt: Date?
    private var pendingRead: PendingDoubaoRead? {
        didSet {
            let enabled = pendingRead != nil
            DispatchQueue.main.async { [weak self] in
                self?.onPendingReadChanged?(enabled)
            }
        }
    }

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
        if !classModeEnabled {
            pendingRead = nil
            if !isSessionRunning {
                floatingWindow.close()
            }
        } else {
            presentSessionIfNeeded()
        }
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
        if action == .classSummary {
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
        Read Doubao Answer: Shift + Return
        Back to Class: Shift + Down
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func bindHUD() {
        floatingWindow.onStartClass = { [weak self] in self?.startClass() }
        floatingWindow.onEndClass = { [weak self] in self?.endClass() }
        floatingWindow.onReviewNote = { [weak self] in self?.reviewClassNote() }
        floatingWindow.onSaveNote = { [weak self] in self?.saveClassNote() }
        floatingWindow.onNewClass = { [weak self] in self?.newClass() }
    }

    func presentSessionIfNeeded() {
        guard classModeEnabled else { return }
        if isSessionRunning {
            startSessionTimerIfNeeded()
            floatingWindow.showClassSession(sessionStore.snapshot())
        } else if sessionStore.session?.summary?.isEmpty == false {
            floatingWindow.showClassSession(sessionStore.snapshot(), detail: sessionStore.session?.summary)
        } else {
            floatingWindow.showClassSession(.idle)
        }
    }

    func startClass() {
        if sessionStore.session?.summary != nil, sessionStore.session?.savePath == nil {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Start a new class?"
            alert.informativeText = "上一节课的总结还没保存。"
            alert.addButton(withTitle: "Start New Class")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        } else if isSessionRunning {
            return
        }

        _ = sessionStore.start()
        pendingInteractionID = nil
        startSessionTimerIfNeeded()
        floatingWindow.showClassSession(sessionStore.snapshot())
        onSessionChanged?()
        DebugLog.write("Class session HUD started")
    }

    func newClass() {
        guard !isSessionRunning else { return }
        if sessionStore.session?.summary != nil, sessionStore.session?.savePath == nil {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Start a new class?"
            alert.informativeText = "上一节课的总结还没保存。"
            alert.addButton(withTitle: "New Class")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        pendingRead = nil
        pendingInteractionID = nil
        stopSessionTimer()
        sessionStore.clear()
        floatingWindow.showClassSession(.idle)
        onSessionChanged?()
        DebugLog.write("Class session HUD reset to Start")
    }

    func endClass() {
        guard isSessionRunning else { return }
        guard !isBusy else {
            floatingWindow.showLoading("等当前操作结束后再结束这节课。", action: .classSummary)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "End Class?"
        alert.informativeText = "停止计时，并把这节课的记录发给豆包做总结。"
        alert.addButton(withTitle: "End Class")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        _ = sessionStore.end()
        stopSessionTimer()
        onSessionChanged?()
        summarizeClass()
    }

    func toggleRecordTranslate() {
        sessionStore.recordTranslate.toggle()
        onSessionChanged?()
    }

    func openNotesFolder() {
        NSWorkspace.shared.open(sessionStore.notesRoot)
    }

    func reviewClassNote() {
        guard let url = sessionStore.writePreviewMarkdown() else { return }
        NSWorkspace.shared.open(url)
    }

    func saveClassNote() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = sessionStore.notesRoot
        panel.nameFieldStringValue = sessionStore.defaultSaveURL().lastPathComponent
        panel.title = "Save Class Note"
        panel.message = "保存为 Markdown。截图会放在同名的 shots 文件夹里。"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try sessionStore.writeNote(to: url)
            floatingWindow.showClassSession(
                sessionStore.snapshot(),
                detail: "已保存到\n\(url.path)"
            )
            onSessionChanged?()
        } catch {
            floatingWindow.showLoading("保存失败：\(error.localizedDescription)", action: .classSummary)
        }
    }

    private func summarizeClass() {
        savePreviousActiveApp()
        let payload = sessionStore.doubaoPayload()
        let prompt = prompts.prompt(for: "classSummary") + "\n\n" + payload
        isBusy = true
        var summarizing = sessionStore.snapshot()
        summarizing.phase = .summarizing
        floatingWindow.showClassSession(summarizing)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard Permissions.hasAccessibilityPermission() else {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.floatingWindow.showLoading("需要辅助功能权限才能让豆包总结。", action: .classSummary)
                    Permissions.showAutomationAlert()
                }
                return
            }

            let result = self.doubao.sendText(prompt, restoreFrontmost: { [weak self] in
                self?.backToClass()
            })
            guard result.success else {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.backToClass()
                    self.floatingWindow.showAnswer(result.userMessage, action: .classSummary)
                }
                return
            }

            self.backToClass()
            self.updatePendingRead(prompt: prompt, action: .classSummary, response: nil)
            DebugLog.write("class summary: sent, waiting for Shift+Return to copy from Doubao")
            DispatchQueue.main.async {
                self.isBusy = false
                self.floatingWindow.showLoading(
                    "已发给豆包做总结。生成完成后按 Shift+Return，会切到豆包并复制。",
                    action: .classSummary
                )
                self.onSessionChanged?()
            }
        }
    }

    private func startSessionTimerIfNeeded() {
        sessionTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isSessionRunning else { return }
            self.floatingWindow.tickClassSession(self.sessionStore.snapshot())
        }
        RunLoop.main.add(timer, forMode: .common)
        sessionTimer = timer
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
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
        pendingInteractionID = sessionStore.beginInteraction(action: action)
        onSessionChanged?()
        DebugLog.write("capture: sent, waiting for Shift+Return to copy from Doubao")
        DispatchQueue.main.async { [weak self] in
            self?.floatingWindow.showLoading(
                "已发送到豆包。生成完成后按 Shift+Return，会切到豆包并复制回答。",
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
        if let lastExtractAt, Date().timeIntervalSince(lastExtractAt) < 5 {
            DebugLog.write("Extract ignored: Shift+Return within 5s cooldown")
            return
        }

        lastExtractAt = Date()
        isBusy = true
        savePreviousActiveApp()
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
        let captured = responseReader.captureCompletedResponse(prompt: prompt, action: action, timeout: 1.2)
        let response = OutputQualityValidator.prepareCopiedForDisplay(captured, action: action, prompt: prompt)

        if action == .classSummary {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let response {
                    self.sessionStore.setSummary(response)
                    self.pendingRead = nil
                    self.floatingWindow.showClassSession(self.sessionStore.snapshot(), detail: response)
                    self.onSessionChanged?()
                } else {
                    self.floatingWindow.showAnswer(
                        "Still generating...\n\n豆包可能还在生成，或 Copy 按钮尚未出现。稍后再按一次 Shift+Return。",
                        action: action
                    )
                }
            }
            return
        }

        updatePendingRead(prompt: prompt, action: action, response: response)
        if let response, let pendingInteractionID {
            sessionStore.finishInteraction(id: pendingInteractionID, answer: response)
            onSessionChanged?()
        }

        DispatchQueue.main.async { [weak self] in
            self?.floatingWindow.showAnswer(response ?? "Still generating...\n\n豆包可能还在生成，或 Copy 按钮尚未出现。稍后再按一次 Shift+Return。", action: action)
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
                expiresAt: Date().addingTimeInterval(action == .classSummary ? 480 : 180)
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
