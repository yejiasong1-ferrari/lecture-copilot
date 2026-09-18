import AppKit

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: generate_app_icon.swift <source.png> <AppIcon.icns>\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let icnsURL = URL(fileURLWithPath: CommandLine.arguments[2])
let resources = icnsURL.deletingLastPathComponent()
guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("failed to read \(sourceURL.path)\n", stderr)
    exit(1)
}

func drawLogo(in box: NSRect) {
    let sourceSize = source.size
    let scale = min(box.width / max(sourceSize.width, 1), box.height / max(sourceSize.height, 1))
    let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let drawRect = NSRect(
        x: box.midX - drawSize.width / 2,
        y: box.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
}

func drawLogoFill(in box: NSRect) {
    let sourceSize = source.size
    let scale = max(box.width / max(sourceSize.width, 1), box.height / max(sourceSize.height, 1))
    let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let drawRect = NSRect(
        x: box.midX - drawSize.width / 2,
        y: box.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    NSBezierPath(rect: box).addClip()
    source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
}

func pngData(pixels: Int, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    draw(rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let masterPNGData = pngData(pixels: 1024) { rect in
    let clip = NSBezierPath(roundedRect: rect, xRadius: 228, yRadius: 228)
    clip.addClip()
    NSColor.white.setFill()
    clip.fill()
    drawLogo(in: rect.insetBy(dx: 86, dy: 86))
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("LectureCopilot.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let masterPNG = iconset.appendingPathComponent("master.png")
try masterPNGData.write(to: masterPNG)

let names: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in names {
    let output = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(pixels)", "\(pixels)", masterPNG.path, "--out", output.path]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        fputs("sips failed for \(name)\n", stderr)
        exit(1)
    }
}

try FileManager.default.removeItem(at: masterPNG)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

let statusPNG = pngData(pixels: 66) { rect in
    let box = rect.insetBy(dx: 1.5, dy: 1.5)
    let radius = box.width * 0.32
    let clip = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    clip.addClip()
    NSColor.white.setFill()
    clip.fill()
    drawLogo(in: box.insetBy(dx: 8, dy: 8))
    NSColor(calibratedRed: 0.52, green: 0.66, blue: 0.80, alpha: 1).setStroke()
    clip.lineWidth = 1.5
    clip.stroke()
}
let hudPNG = pngData(pixels: 128) { rect in
    drawLogoFill(in: rect)
}
try statusPNG.write(to: resources.appendingPathComponent("StatusIcon.png"))
try hudPNG.write(to: resources.appendingPathComponent("HUDIcon.png"))
try masterPNGData.write(to: resources.appendingPathComponent("AppIcon.png"))
print("Wrote \(icnsURL.path)")
