import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusController = StatusController()
    private let hotKeyController = HotKeyController()
    private let copilot = LectureCopilotController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController.delegate = self
        renderMenu()

        hotKeyController.onHotKey = { [weak self] event in
            self?.copilot.handle(event)
            self?.renderMenu()
        }
        hotKeyController.shouldHandleReturnKey = { [weak self] in
            self?.copilot.shouldHandleReturnKey() ?? false
        }

        copilot.onClassModeChanged = { [weak self] _ in
            self?.renderMenu()
        }
        copilot.onPendingReadChanged = { [weak self] enabled in
            self?.hotKeyController.setReturnHotKeyEnabled(enabled)
        }
        copilot.onSessionChanged = { [weak self] in
            self?.renderMenu()
        }

        copilot.bindHUD()
        hotKeyController.start()
        copilot.presentSessionIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController.stop()
    }

    @objc func runLastCaptureExplain() {
        copilot.runLastCapture(.explain)
    }

    @objc func runLastCaptureDirectAnswer() {
        copilot.runLastCapture(.directAnswer)
    }

    @objc func runLastCaptureSayInClass() {
        copilot.runLastCapture(.sayInClass)
    }

    @objc func extractPendingAnswer() {
        copilot.extractPendingAnswer()
    }
}

extension AppDelegate: StatusControllerDelegate {
    func statusControllerDidToggleClassMode(_ statusController: StatusController) {
        copilot.toggleClassMode()
    }

    func statusControllerDidChooseAction(_ statusController: StatusController, action: CopilotAction) {
        copilot.run(action)
    }

    func statusControllerDidChooseOpenDoubao(_ statusController: StatusController) {
        copilot.openDoubao()
    }

    func statusControllerDidChoosePromptSettings(_ statusController: StatusController) {
        copilot.openPromptSettings()
    }

    func statusControllerDidChooseLastAnswer(_ statusController: StatusController) {
        copilot.openLastAnswer()
    }

    func statusControllerDidChooseInspectDoubao(_ statusController: StatusController) {
        copilot.inspectDoubao()
    }

    func statusControllerDidChooseTranslateLastCapture(_ statusController: StatusController) {
        copilot.translateLastCapture()
    }

    func statusControllerDidChooseShortcutSettings(_ statusController: StatusController) {
        copilot.showShortcutSettings()
    }

    func statusControllerDidChooseStartClass(_ statusController: StatusController) {
        copilot.startClass()
        renderMenu()
    }

    func statusControllerDidChooseEndClass(_ statusController: StatusController) {
        copilot.endClass()
        renderMenu()
    }

    func statusControllerDidToggleRecordTranslate(_ statusController: StatusController) {
        copilot.toggleRecordTranslate()
        renderMenu()
    }

    func statusControllerDidChooseNotesFolder(_ statusController: StatusController) {
        copilot.openNotesFolder()
    }
}

private extension AppDelegate {
    func renderMenu() {
        statusController.render(
            classModeEnabled: copilot.classModeEnabled,
            sessionRunning: copilot.isSessionRunning,
            recordTranslate: copilot.recordTranslateEnabled,
            noteCount: copilot.sessionNoteCount
        )
    }
}
