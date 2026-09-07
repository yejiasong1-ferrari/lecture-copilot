import AppKit
import CoreGraphics

enum DoubaoWindow {
    static let chatAppNames = ["豆包", "Doubao"]
    static let lastCaptureURL = DebugLog.directory.appendingPathComponent("last-capture.png")
    static let conversationBaselineURL = DebugLog.directory.appendingPathComponent("last-conversation-baseline.png")

    enum Region {
        case full
        case composer
        case conversation
    }

    static func runningChatApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            chatAppNames.contains(app.localizedName ?? "")
        }
    }

    static func largestWindow() -> (bounds: CGRect, windowID: CGWindowID)? {
        let pids = Set(
            NSWorkspace.shared.runningApplications
                .filter { chatAppNames.contains($0.localizedName ?? "") }
                .map(\.processIdentifier)
        )
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates: [(bounds: CGRect, windowID: CGWindowID)] = windows.compactMap { info in
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

        return candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
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
}
