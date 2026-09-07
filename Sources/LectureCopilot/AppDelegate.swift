import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusController = StatusController()
    private let hotKeyController = HotKeyController()
    private let copilot = LectureCopilotController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController.delegate = self
        statusController.render(classModeEnabled: copilot.classModeEnabled)

        hotKeyController.onHotKey = { [weak self] event in
            self?.copilot.handle(event)
            self?.statusController.render(classModeEnabled: self?.copilot.classModeEnabled ?? false)
        }
        hotKeyController.shouldHandleReturnKey = { [weak self] in
            self?.copilot.shouldHandleReturnKey() ?? false
        }

        copilot.onClassModeChanged = { [weak self] enabled in
            self?.statusController.render(classModeEnabled: enabled)
        }

        hotKeyController.start()
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
}
