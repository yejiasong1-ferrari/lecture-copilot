import AppKit

final class ScreenshotCapture {
    private let lastCaptureURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lecture Copilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("last-capture.png")
    }()

    func captureSelectionToClipboard() -> Bool {
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", lastCaptureURL.path]

        do {
            try? FileManager.default.removeItem(at: lastCaptureURL)
            try process.run()
            process.waitUntilExit()
            DebugLog.write("screencapture exited with status \(process.terminationStatus)")
            guard process.terminationStatus == 0 else { return false }
            let bytes = fileSize(lastCaptureURL)
            guard bytes > 1024 else {
                DebugLog.write("[capture] fail path=\(lastCaptureURL.path) bytes=\(bytes)")
                return false
            }
            guard copyLastCaptureToPasteboard() else { return false }
            DebugLog.write(String(
                format: "[capture] success path=%@ bytes=%d elapsed=%.0fms",
                lastCaptureURL.path,
                bytes,
                Date().timeIntervalSince(started) * 1000
            ))
            return true
        } catch {
            DebugLog.write("Failed to run screencapture: \(error.localizedDescription)")
            return false
        }
    }

    func prepareLastCapture() -> Bool {
        copyLastCaptureToPasteboard()
    }

    func importCapture(from url: URL) -> Bool {
        try? FileManager.default.removeItem(at: lastCaptureURL)
        do {
            try FileManager.default.copyItem(at: url, to: lastCaptureURL)
        } catch {
            DebugLog.write("Failed to import capture: \(error.localizedDescription)")
            return false
        }
        return copyLastCaptureToPasteboard()
    }

    private func copyLastCaptureToPasteboard() -> Bool {
        guard let image = NSImage(contentsOf: lastCaptureURL),
              let pngData = pngData(from: image) ?? (try? Data(contentsOf: lastCaptureURL)) else {
            DebugLog.write("No captured image found at \(lastCaptureURL.path)")
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.writeObjects([image])
        DebugLog.write("Captured image saved to \(lastCaptureURL.path) and copied to pasteboard")
        return true
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
