import AppKit

final class CopyIconFinder {
    struct Match {
        let point: CGPoint
        let score: Double
    }

    private let templatePixels: [UInt8]
    private let templateWidth: Int
    private let templateHeight: Int

    init?() {
        guard let image = Self.loadTemplate()?.cgImage else {
            DebugLog.write("Copy icon template not found")
            return nil
        }

        let gray = Self.grayscale(image)
        templatePixels = gray.pixels
        templateWidth = gray.width
        templateHeight = gray.height
        DebugLog.write("Copy icon template loaded \(templateWidth)x\(templateHeight)")
    }

    func match(in windowImage: CGImage, windowBounds: CGRect) -> Match? {
        let source = downsample(windowImage, maxWidth: 720) ?? windowImage
        let gray = Self.grayscale(source)
        let searchLeft = Int(Double(gray.width) * 0.18)
        let searchTop = Int(Double(gray.height) * 0.62)
        let searchRight = Int(Double(gray.width) * 0.48)
        let searchBottom = Int(Double(gray.height) * 0.93)

        var bestScore = -Double.greatestFiniteMagnitude
        var bestX = 0
        var bestY = 0
        var bestWidth = templateWidth
        var bestHeight = templateHeight

        for scale in [0.24, 0.30, 0.38] {
            let tw = max(12, Int(Double(templateWidth) * scale))
            let th = max(10, Int(Double(templateHeight) * scale))
            guard searchRight - searchLeft > tw, searchBottom - searchTop > th else { continue }

            let scaled = scaleTemplate(width: tw, height: th)
            let step = max(2, tw / 10)

            var y = searchTop
            while y <= searchBottom - th {
                var x = searchLeft
                while x <= searchRight - tw {
                    let score = normalizedCorrelation(
                        image: gray.pixels,
                        imageWidth: gray.width,
                        originX: x,
                        originY: y,
                        template: scaled,
                        templateWidth: tw,
                        templateHeight: th
                    )
                    if score > bestScore {
                        bestScore = score
                        bestX = x
                        bestY = y
                        bestWidth = tw
                        bestHeight = th
                    }
                    x += step
                }
                y += step
            }
        }

        DebugLog.write(String(format: "Copy icon best score %.3f at image (%d,%d)", bestScore, bestX, bestY))
        guard bestScore >= 0.78 else { return nil }

        let px = (CGFloat(bestX) + CGFloat(bestWidth) / 2) / CGFloat(source.width)
        let py = (CGFloat(bestY) + CGFloat(bestHeight) / 2) / CGFloat(source.height)
        let point = CGPoint(
            x: windowBounds.minX + px * windowBounds.width,
            y: windowBounds.minY + py * windowBounds.height
        )
        return Match(point: point, score: bestScore)
    }

    private func downsample(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let scale = CGFloat(maxWidth) / CGFloat(image.width)
        let height = max(1, Int(CGFloat(image.height) * scale))
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: maxWidth,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: maxWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }

    private func scaleTemplate(width: Int, height: Int) -> [UInt8] {
        if width == templateWidth, height == templateHeight {
            return templatePixels
        }

        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let srcY = min(templateHeight - 1, y * templateHeight / height)
            for x in 0..<width {
                let srcX = min(templateWidth - 1, x * templateWidth / width)
                output[y * width + x] = templatePixels[srcY * templateWidth + srcX]
            }
        }
        return output
    }

    private func normalizedCorrelation(
        image: [UInt8],
        imageWidth: Int,
        originX: Int,
        originY: Int,
        template: [UInt8],
        templateWidth: Int,
        templateHeight: Int
    ) -> Double {
        let count = Double(templateWidth * templateHeight)
        var imageSum = 0.0
        var templateSum = 0.0

        for ty in 0..<templateHeight {
            let imageRow = (originY + ty) * imageWidth + originX
            let templateRow = ty * templateWidth
            for tx in 0..<templateWidth {
                imageSum += Double(image[imageRow + tx])
                templateSum += Double(template[templateRow + tx])
            }
        }

        let imageMean = imageSum / count
        let templateMean = templateSum / count
        var numerator = 0.0
        var imageDenom = 0.0
        var templateDenom = 0.0

        for ty in 0..<templateHeight {
            let imageRow = (originY + ty) * imageWidth + originX
            let templateRow = ty * templateWidth
            for tx in 0..<templateWidth {
                let imageDelta = Double(image[imageRow + tx]) - imageMean
                let templateDelta = Double(template[templateRow + tx]) - templateMean
                numerator += imageDelta * templateDelta
                imageDenom += imageDelta * imageDelta
                templateDenom += templateDelta * templateDelta
            }
        }

        let denominator = sqrt(imageDenom * templateDenom)
        guard denominator > 1 else { return -1 }
        return numerator / denominator
    }

    private static func loadTemplate() -> NSImage? {
        let candidates: [URL] = [
            Bundle.main.url(forResource: "copy-icon-template", withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("copy-icon-template.png"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/copy-icon-template.png")
        ].compactMap { $0 }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        DebugLog.write("Copy icon template missing from \(candidates.map(\.path))")
        return nil
    }

    private static func grayscale(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { raw in
            if let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) {
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        return (pixels, width, height)
    }
}

private extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
            ?? tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.cgImage }
    }
}
