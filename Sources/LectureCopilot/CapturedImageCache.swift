import AppKit

final class CapturedImageCache {
    private let ttl: TimeInterval
    private var capturedAt: Date?
    private var pngData: Data?
    private var tiffData: Data?

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func storeCurrentPasteboardImage() {
        let pasteboard = NSPasteboard.general
        pngData = pasteboard.data(forType: .png)
        tiffData = pasteboard.data(forType: .tiff)
        capturedAt = Date()
    }

    func restoreToPasteboardIfFresh() -> Bool {
        guard let capturedAt, Date().timeIntervalSince(capturedAt) <= ttl else {
            clear()
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let pngData {
            pasteboard.setData(pngData, forType: .png)
            return true
        }

        if let tiffData {
            pasteboard.setData(tiffData, forType: .tiff)
            return true
        }

        return false
    }

    private func clear() {
        capturedAt = nil
        pngData = nil
        tiffData = nil
    }
}
