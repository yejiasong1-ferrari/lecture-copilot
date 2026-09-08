import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct DoubaoUploadResult {
    let success: Bool
    let abortReason: String

    var userMessage: String {
        switch abortReason {
        case "ABORT_IMAGE_ATTACH":
            return "截图没有贴进豆包输入框，这次没有发送，以免读到旧聊天。请再试一次。"
        case "SEND_FAILED":
            return "已经贴上截图，但豆包没有发出去。请看一眼豆包窗口后再试。"
        case "Doubao is not running":
            return "豆包没有在运行。"
        case "image missing":
            return "没有找到要发送的截图。"
        default:
            return abortReason.isEmpty
                ? "没有成功发送到豆包。"
                : "没有成功发送到豆包（\(abortReason)）。"
        }
    }
}

final class DoubaoUploadFSM {
    private enum State {
        case activateDoubao
        case openNewChat
        case waitChatReady
        case snapshotComposerBaseline
        case pasteImage
        case verifyAttachment
        case retryPasteImage
        case typePrompt
        case sendMessage
        case verifySent
        case retrySend
        case restoreAndFinish
        case abort
    }

    private struct Job {
        let id: UUID
        let startedAt: Date
        let prompt: String
        let imageURL: URL?
        let log: JobLog
        var restoreFrontmost: (() -> Void)?
        var composerBaseline: CGImage?
        var conversationBaseline: CGImage?
        var attachedComposer: CGImage?
        var promptedComposer: CGImage?
        var preSendConversation: CGImage?
        var preSendComposer: CGImage?
        var attachmentVerified = false
        var sendVerified = false
        var pasteAttempts = 0
        var sendAttempts = 0
        var abortReason = ""
    }

    private let attachDiffThreshold = 0.012
    private let attachStableThreshold = 0.05
    private let stableDiffThreshold = 0.018
    private let sentDiffThreshold = 0.02

    @discardableResult
    func run(prompt: String, imageURL: URL?, restoreFrontmost: (() -> Void)?) -> DoubaoUploadResult {
        let jobID = UUID()
        var job = Job(
            id: jobID,
            startedAt: Date(),
            prompt: prompt,
            imageURL: imageURL.flatMap { copyJobImage(from: $0, jobID: jobID) } ?? imageURL,
            log: JobLog(jobID),
            restoreFrontmost: restoreFrontmost
        )
        job.log.state("UPLOAD", "start")

        var state = State.activateDoubao
        while true {
            switch state {
            case .activateDoubao:
                state = activateDoubao(&job)
            case .openNewChat:
                state = openNewChat(&job)
            case .waitChatReady:
                state = waitChatReady(&job)
            case .snapshotComposerBaseline:
                state = snapshotComposerBaseline(&job)
            case .pasteImage:
                state = pasteImage(&job)
            case .verifyAttachment:
                state = verifyAttachment(&job)
            case .retryPasteImage:
                state = retryPasteImage(&job)
            case .typePrompt:
                state = typePrompt(&job)
            case .sendMessage:
                state = sendMessage(&job)
            case .verifySent:
                state = verifySent(&job)
            case .retrySend:
                state = retrySend(&job)
            case .restoreAndFinish:
                restore(&job)
                job.log.done(elapsed: Date().timeIntervalSince(job.startedAt))
                return DoubaoUploadResult(success: job.attachmentVerified && job.sendVerified, abortReason: "")
            case .abort:
                job.log.state("ABORT", job.abortReason)
                restore(&job)
                job.log.done(elapsed: Date().timeIntervalSince(job.startedAt))
                return DoubaoUploadResult(success: false, abortReason: job.abortReason)
            }
        }
    }

    private func activateDoubao(_ job: inout Job) -> State {
        let started = Date()
        guard let app = ensureChatApp(job.log) else {
            job.abortReason = "Doubao is not running"
            job.log.state("ACTIVATE_DOUBAO", "fail", extra: job.abortReason, elapsed: Date().timeIntervalSince(started))
            return .abort
        }

        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        let frontmost = AXAccess.waitUntil(timeout: 1.2) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        }
        job.log.state(
            "ACTIVATE_DOUBAO",
            frontmost ? "success" : "timeout",
            extra: "pid=\(app.processIdentifier)",
            elapsed: Date().timeIntervalSince(started)
        )
        return .openNewChat
    }

    private func openNewChat(_ job: inout Job) -> State {
        let started = Date()
        let before = DoubaoWindow.capture(.conversation)
        var method = "none"

        if let app = DoubaoWindow.runningChatApp() {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            if pressNewChatMenu(in: axApp) {
                method = "AXMenu"
            } else {
                postKey(53, flags: [])
                _ = AXAccess.waitUntil(timeout: 0.05) { false }
                postKey(45, flags: .maskCommand)
                method = "Cmd+N"
            }
        }

        let changed = AXAccess.waitUntil(timeout: 1.6) {
            ImageDiff.ratio(before, DoubaoWindow.capture(.conversation)) > sentDiffThreshold
        }
        job.log.state(
            "OPEN_NEW_CHAT",
            changed ? "success" : "unchanged",
            extra: "method=\(method)",
            elapsed: Date().timeIntervalSince(started)
        )
        return .waitChatReady
    }

    private func waitChatReady(_ job: inout Job) -> State {
        let started = Date()
        var previous = DoubaoWindow.capture(.composer)
        var skippedFirstTick = false
        let ready = AXAccess.waitUntil(timeout: 3, interval: 0.1) {
            let current = DoubaoWindow.capture(.composer)
            defer { previous = current }
            guard skippedFirstTick else {
                skippedFirstTick = true
                return false
            }
            return ImageDiff.ratio(previous, current) < stableDiffThreshold
        }

        job.log.state(
            "WAIT_CHAT_READY",
            ready ? "success" : "timeout",
            extra: "hash=\(ImageDiff.fingerprint(previous))",
            elapsed: Date().timeIntervalSince(started)
        )
        return .snapshotComposerBaseline
    }

    private func snapshotComposerBaseline(_ job: inout Job) -> State {
        let started = Date()
        job.composerBaseline = DoubaoWindow.capture(.composer)
        job.conversationBaseline = DoubaoWindow.capture(.conversation)
        job.log.state(
            "SNAPSHOT_COMPOSER_BASELINE",
            job.composerBaseline == nil ? "missing" : "success",
            extra: "composer=\(ImageDiff.fingerprint(job.composerBaseline))",
            elapsed: Date().timeIntervalSince(started)
        )
        if job.imageURL == nil {
            job.attachmentVerified = true
            return .typePrompt
        }
        return .pasteImage
    }

    private func pasteImage(_ job: inout Job) -> State {
        let started = Date()
        guard let imageURL = job.imageURL, copyImageToPasteboard(imageURL) else {
            job.abortReason = "image missing"
            job.log.state("PASTE_IMAGE", "fail", extra: job.abortReason, elapsed: Date().timeIntervalSince(started))
            return .abort
        }

        job.pasteAttempts += 1
        focusComposer()
        _ = AXAccess.waitUntil(timeout: 0.12) { false }
        postKey(9, flags: .maskCommand)
        job.log.state("PASTE_IMAGE", "Cmd+V", extra: "attempt=\(job.pasteAttempts)", elapsed: Date().timeIntervalSince(started))
        return .verifyAttachment
    }

    private func verifyAttachment(_ job: inout Job) -> State {
        let started = Date()
        var lastMatch: CGImage?
        var latest: CGImage?
        var stableHits = 0
        var bestDiff = 0.0
        var lastDiff = 0.0

        _ = AXAccess.waitUntil(timeout: 1.25, interval: 0.05) {
            let current = DoubaoWindow.capture(.composer)
            latest = current
            let diff = ImageDiff.ratio(job.composerBaseline, current)
            lastDiff = diff
            bestDiff = max(bestDiff, diff)
            guard diff >= attachDiffThreshold else {
                stableHits = 0
                lastMatch = current
                return false
            }
            if let lastMatch, ImageDiff.ratio(lastMatch, current) < attachStableThreshold {
                stableHits += 1
            } else {
                stableHits = 1
            }
            lastMatch = current
            if stableHits >= 2 {
                job.attachedComposer = current
                return true
            }
            return false
        }

        // Doubao thumbnails often flicker just below the threshold while still
        // attaching. Treat that as success so we do not Cmd+V a second copy.
        let attached = stableHits >= 2
            || lastDiff >= attachDiffThreshold
            || (bestDiff >= attachDiffThreshold && lastDiff >= attachDiffThreshold * 0.75)
        if attached {
            job.attachmentVerified = true
            job.attachedComposer = latest ?? lastMatch
            job.log.state(
                "VERIFY_ATTACHMENT",
                "success",
                extra: String(format: "diff=%.3f last=%.3f hits=%d confidence=%.2f", bestDiff, lastDiff, stableHits, min(0.99, bestDiff / 0.04)),
                elapsed: Date().timeIntervalSince(started)
            )
            return .typePrompt
        }

        DoubaoWindow.save(job.composerBaseline, to: DebugLog.directory.appendingPathComponent("last-composer-baseline.png"))
        DoubaoWindow.save(latest, to: DebugLog.directory.appendingPathComponent("last-composer-after.png"))
        job.log.state(
            "VERIFY_ATTACHMENT",
            "fail",
            extra: String(format: "diff=%.3f last=%.3f attempt=%d", bestDiff, lastDiff, job.pasteAttempts),
            elapsed: Date().timeIntervalSince(started)
        )
        return job.pasteAttempts < 2 ? .retryPasteImage : abort(&job, reason: "ABORT_IMAGE_ATTACH")
    }

    private func retryPasteImage(_ job: inout Job) -> State {
        let started = Date()
        var latest: CGImage?
        let alreadyAttached = AXAccess.waitUntil(timeout: 0.6, interval: 0.05) {
            latest = DoubaoWindow.capture(.composer)
            return ImageDiff.ratio(job.composerBaseline, latest) >= attachDiffThreshold
        }
        if alreadyAttached {
            job.attachmentVerified = true
            job.attachedComposer = latest
            job.log.state(
                "RETRY_PASTE_IMAGE",
                "already attached",
                extra: String(format: "diff=%.3f", ImageDiff.ratio(job.composerBaseline, latest)),
                elapsed: Date().timeIntervalSince(started)
            )
            return .typePrompt
        }

        job.log.state("RETRY_PASTE_IMAGE", "retry", elapsed: Date().timeIntervalSince(started))
        return pasteImage(&job)
    }

    private func typePrompt(_ job: inout Job) -> State {
        let started = Date()
        guard job.attachmentVerified else {
            return abort(&job, reason: "ABORT_IMAGE_ATTACH")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(job.prompt, forType: .string)

        focusComposer()
        postKey(9, flags: .maskCommand)
        let wait = job.prompt.count > 600 ? 1.0 : 0.35
        _ = AXAccess.waitUntil(timeout: wait, interval: 0.05) {
            ImageDiff.ratio(job.attachedComposer ?? job.composerBaseline, DoubaoWindow.capture(.composer)) > 0.008
        }
        job.promptedComposer = DoubaoWindow.capture(.composer)
        job.log.state("TYPE_PROMPT", "success", extra: "method=clipboard", elapsed: Date().timeIntervalSince(started))
        return .sendMessage
    }

    private func sendMessage(_ job: inout Job) -> State {
        let started = Date()
        job.sendAttempts += 1
        job.preSendConversation = DoubaoWindow.capture(.conversation)
        job.preSendComposer = DoubaoWindow.capture(.composer)
        postKey(36, flags: [])
        job.log.state("SEND", "Return", extra: "attempt=\(job.sendAttempts)", elapsed: Date().timeIntervalSince(started))
        return .verifySent
    }

    private func verifySent(_ job: inout Job) -> State {
        let started = Date()
        let sent = AXAccess.waitUntil(timeout: job.prompt.count > 600 ? 1.2 : 0.55, interval: 0.05) {
            let composerChanged = ImageDiff.ratio(job.preSendComposer, DoubaoWindow.capture(.composer)) > sentDiffThreshold
            let conversationChanged = ImageDiff.ratio(job.preSendConversation, DoubaoWindow.capture(.conversation)) > sentDiffThreshold
            return composerChanged || conversationChanged
        }

        if sent {
            job.sendVerified = true
            DoubaoWindow.save(
                DoubaoWindow.capture(.conversation) ?? job.conversationBaseline,
                to: DoubaoWindow.conversationBaselineURL
            )
            job.log.state("VERIFY_SENT", "success", extra: "method=Return", elapsed: Date().timeIntervalSince(started))
            return .restoreAndFinish
        }

        job.log.state("VERIFY_SENT", "fail", extra: "attempt=\(job.sendAttempts)", elapsed: Date().timeIntervalSince(started))
        return job.sendAttempts < 2 ? .retrySend : abort(&job, reason: "SEND_FAILED")
    }

    private func retrySend(_ job: inout Job) -> State {
        job.log.state("RETRY_SEND", "retry")
        return sendMessage(&job)
    }

    private func abort(_ job: inout Job, reason: String) -> State {
        job.abortReason = reason
        return .abort
    }

    private func restore(_ job: inout Job) {
        let started = Date()
        job.restoreFrontmost?()
        job.log.state("RESTORE_APP", "success", elapsed: Date().timeIntervalSince(started))
    }

    private func ensureChatApp(_ log: JobLog) -> NSRunningApplication? {
        if let running = DoubaoWindow.runningChatApp() {
            return running
        }

        log.state("ACTIVATE_DOUBAO", "launching")
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Doubao.app"))
        _ = AXAccess.waitUntil(timeout: 8) { DoubaoWindow.runningChatApp() != nil }
        return DoubaoWindow.runningChatApp()
    }

    private func pressNewChatMenu(in axApp: AXUIElement) -> Bool {
        let titles = ["新建对话", "New Chat", "New Conversation"]
        guard let fileItem = AXAccess.menuBarItem(named: ["文件", "File"], in: axApp) else {
            return false
        }

        if let item = AXAccess.menuItem(named: titles, inMenuBarItem: fileItem), AXAccess.press(item) {
            return true
        }

        guard AXAccess.press(fileItem) else { return false }
        let appeared = AXAccess.waitUntil(timeout: 0.4) {
            AXAccess.menuItem(named: titles, inMenuBarItem: fileItem) != nil
        }
        guard appeared, let item = AXAccess.menuItem(named: titles, inMenuBarItem: fileItem) else {
            return false
        }
        return AXAccess.press(item)
    }

    private func focusComposer() {
        DoubaoWindow.runningChatApp()?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let pid = DoubaoWindow.runningChatApp()?.processIdentifier,
           let composer = findComposer(in: AXUIElementCreateApplication(pid)) {
            _ = AXAccess.setFocused(composer)
            return
        }
        clickComposer()
    }

    private func findComposer(in axApp: AXUIElement) -> AXUIElement? {
        var areas: [AXUIElement] = []
        for window in AXAccess.windows(of: axApp) {
            guard let windowFrame = AXAccess.frame(window) else { continue }
            AXAccess.collect(window, into: &areas) { element in
                let role = AXAccess.role(element)
                guard role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String),
                      let frame = AXAccess.frame(element),
                      frame.width > 300,
                      frame.height > 30,
                      frame.minY >= windowFrame.midY else {
                    return false
                }
                return true
            }
        }
        return areas.max { lhs, rhs in
            (AXAccess.frame(lhs)?.minY ?? 0) < (AXAccess.frame(rhs)?.minY ?? 0)
        }
    }

    private func clickComposer() {
        guard let point = DoubaoWindow.composerPoint() else { return }
        CGWarpMouseCursorPosition(point)
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func copyImageToPasteboard(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else {
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        if let png = try? Data(contentsOf: url) {
            pasteboard.setData(png, forType: .png)
        }
        return true
    }

    private func copyJobImage(from source: URL, jobID: UUID) -> URL? {
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let dest = DebugLog.directory.appendingPathComponent("capture-\(JobLog(jobID).id).png")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return source
        }
    }

    private func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
