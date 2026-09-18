import AppKit
import ApplicationServices
import CoreGraphics

enum DoubaoWindow {
    static let chatAppNames = ["豆包", "Doubao"]
    static let chatBundleIDs = ["com.bot.pc.doubao"]
    static let lastCaptureURL = DebugLog.directory.appendingPathComponent("last-capture.png")
    static let conversationBaselineURL = DebugLog.directory.appendingPathComponent("last-conversation-baseline.png")

    enum Region {
        case full
        case composer
        case conversation
    }

    static func isChatApp(_ app: NSRunningApplication) -> Bool {
        if let bundleID = app.bundleIdentifier, chatBundleIDs.contains(bundleID) {
            return true
        }
        return chatAppNames.contains(app.localizedName ?? "")
    }

    static func runningChatApp() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter(isChatApp)
        return apps.first(where: { $0.activationPolicy == .regular }) ?? apps.first
    }

    static func isFrontmost() -> Bool {
        guard let app = runningChatApp() else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    @discardableResult
    static func makeFrontmost(timeout: TimeInterval = 4.5) -> Bool {
        guard let app = runningChatApp() else { return false }
        DebugLog.write(
            "Activate Doubao pid=\(app.processIdentifier) hidden=\(app.isHidden) active=\(app.isActive) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")"
        )
        app.unhide()
        let activate = {
            yieldActivation(to: app)
            openApplication(app)
            activateWithAppleScript(bundleID: app.bundleIdentifier ?? chatBundleIDs[0])
            setProcessFrontmost(pid: app.processIdentifier)
            raiseAXWindows(pid: app.processIdentifier)
        }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }

        var lastRetry = Date.distantPast
        let switched = AXAccess.waitUntil(timeout: timeout, interval: 0.08) {
            if !isFrontmost(), Date().timeIntervalSince(lastRetry) > 0.5 {
                lastRetry = Date()
                let retry = {
                    yieldActivation(to: app)
                    setProcessFrontmost(pid: app.processIdentifier)
                    raiseAXWindows(pid: app.processIdentifier)
                }
                if Thread.isMainThread {
                    retry()
                } else {
                    DispatchQueue.main.sync(execute: retry)
                }
            }
            return isFrontmost() && onscreenChatWindow() != nil
        }
        DebugLog.write(
            "Activate Doubao \(switched ? "success" : "fail") front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none") window=\(String(describing: onscreenChatWindow()?.bounds))"
        )
        return switched
    }

    static func largestWindow() -> (bounds: CGRect, windowID: CGWindowID)? {
        onscreenChatWindow() ?? allChatWindows().max {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }
    }

    static func capture(_ region: Region) -> CGImage? {
        guard let target = largestWindow() else { return nil }
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            target.windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }
        return crop(image, region: region)
    }

    static func save(_ image: CGImage?, to url: URL) {
        guard let image else { return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }

    static func composerPoint() -> CGPoint? {
        guard let window = largestWindow() else { return nil }
        return CGPoint(
            x: window.bounds.minX + window.bounds.width * 0.58,
            y: window.bounds.maxY - 72
        )
    }

    private static func crop(_ image: CGImage, region: Region) -> CGImage {
        guard image.width >= 400, image.height >= 300 else {
            return image
        }

        let cropRect: CGRect
        switch region {
        case .full:
            return image
        case .composer:
            cropRect = CGRect(
                x: Double(image.width) * 0.14,
                y: Double(image.height) * 0.52,
                width: Double(image.width) * 0.80,
                height: Double(image.height) * 0.44
            )
        case .conversation:
            cropRect = CGRect(
                x: Double(image.width) * 0.16,
                y: Double(image.height) * 0.08,
                width: Double(image.width) * 0.78,
                height: Double(image.height) * 0.60
            )
        }

        return image.cropping(to: cropRect) ?? image
    }

    private static func yieldActivation(to app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    private static func openApplication(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                DebugLog.write("Open Doubao failed: \(error.localizedDescription)")
            }
        }
    }

    private static func activateWithAppleScript(bundleID: String) {
        let escaped = bundleID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application id "\(escaped)"
            activate
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            DebugLog.write("Doubao AppleScript activate failed: \(error)")
        }
    }

    private static func setProcessFrontmost(pid: pid_t) {
        let source = """
        tell application "System Events"
            set frontmost of (first process whose unix id is \(pid)) to true
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            DebugLog.write("Doubao System Events frontmost failed: \(error)")
        }
    }

    private static func raiseAXWindows(pid: pid_t) {
        for window in AXAccess.windows(of: AXUIElementCreateApplication(pid)) {
            AXAccess.makeMainWindow(window)
        }
    }

    private static func chatPIDs() -> Set<pid_t> {
        Set(NSWorkspace.shared.runningApplications.filter(isChatApp).map(\.processIdentifier))
    }

    private static func onscreenChatWindow() -> (bounds: CGRect, windowID: CGWindowID)? {
        chatWindows(onScreenOnly: true).max {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }
    }

    private static func allChatWindows() -> [(bounds: CGRect, windowID: CGWindowID)] {
        chatWindows(onScreenOnly: false)
    }

    private static func chatWindows(onScreenOnly: Bool) -> [(bounds: CGRect, windowID: CGWindowID)] {
        let pids = chatPIDs()
        guard !pids.isEmpty else { return [] }
        let option: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windows.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pids.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowNumber = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 300,
                  bounds.height >= 200 else {
                return nil
            }
            return (bounds, CGWindowID(windowNumber))
        }
    }
}
