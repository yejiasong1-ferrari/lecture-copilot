import AppKit
import ApplicationServices

enum Permissions {
    private static var hasShownScreenCaptureAlert = false

    static func showAccessibilityAlert() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        let alert = NSAlert()
        alert.messageText = "Enable Accessibility for Lecture Copilot"
        alert.informativeText = "Global shortcuts and Doubao automation need Accessibility permission. Open System Settings > Privacy & Security > Accessibility, then enable Lecture Copilot."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func showAutomationAlert() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let alert = NSAlert()
        alert.messageText = "请打开辅助功能权限"
        alert.informativeText = "Lecture Copilot 需要辅助功能权限，才能代替你操作豆包：粘贴截图、输入提示词并发送。请在系统设置 > 隐私与安全性 > 辅助功能中，添加并打开 Lecture Copilot。"
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "稍后处理")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenCapturePermission(completion: @escaping (Bool) -> Void) {
        // Request from the foreground app so macOS associates approval with this bundle.
        let granted = CGRequestScreenCaptureAccess()
        DispatchQueue.main.async {
            completion(granted || CGPreflightScreenCaptureAccess())
        }
    }

    static func showScreenCaptureAlert() {
        guard !hasShownScreenCaptureAlert else { return }
        hasShownScreenCaptureAlert = true

        let alert = NSAlert()
        alert.messageText = "请打开屏幕录制权限"
        let appPath = Bundle.main.bundlePath
        alert.informativeText = "Lecture Copilot 需要“屏幕录制与系统音频录制”权限，才能框选课堂内容。请在列表中添加并打开 \(appPath)，然后退出并重新打开 Lecture Copilot。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
