import AppKit

final class CopyIconFinder {
    struct Match {
        let point: CGPoint
        let score: Double
    }

    private let templatePixels: [UInt8]
    private let templateWidth: Int
    private let templateHeight: Int

    init?(templateURL: URL? = nil) {
        let templateImage = templateURL.flatMap { NSImage(contentsOf: $0) } ?? Self.loadTemplate()
        guard let image = templateImage?.cgImage else {
            DebugLog.write("Copy icon template not found")
            return nil
        }

        let gray = Self.grayscale(image)
        templatePixels = gray.pixels
        templateWidth = gray.width
        templateHeight = gray.height
        DebugLog.write("Copy icon template loaded \(templateWidth)x\(templateHeight)")
    }

    func match(in windowImage: CGImage, windowBounds: CGRect, preferredXRatio: CGFloat? = nil) -> Match? {
        let source = downsample(windowImage, maxWidth: 720) ?? windowImage
        let gray = Self.grayscale(source)
        // Doubao can show the answer without its left sidebar, putting the
        // first action (Copy) very close to the window's left edge.
        let leftRatio = preferredXRatio.map { max(0.02, Double($0) - 0.045) } ?? 0.02
        let rightRatio = preferredXRatio.map { min(0.52, Double($0) + 0.045) } ?? 0.52
        let searchLeft = Int(Double(gray.width) * leftRatio)
        let searchTop = Int(Double(gray.height) * 0.55)
        let searchRight = Int(Double(gray.width) * rightRatio)
        let searchBottom = Int(Double(gray.height) * 0.96)

        var bestScore = -Double.greatestFiniteMagnitude
        var bestX = 0
        var bestY = 0
        var bestWidth = templateWidth
        var bestHeight = templateHeight

        for scale in [0.20, 0.22, 0.24, 0.25, 0.27, 0.30, 0.34] {
            let tw = max(12, Int(Double(templateWidth) * scale))
            let th = max(10, Int(Double(templateHeight) * scale))
            guard searchRight - searchLeft > tw, searchBottom - searchTop > th else { continue }

            let scaled = scaleTemplate(width: tw, height: th)
            // At the downsampled size a one-pixel shift is several screen
            // pixels. A two-pixel stride can skip the small overlapping-square
            // icon completely.
            let step = 1

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
        guard bestScore >= 0.70 else { return nil }

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
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }

    private func scaleTemplate(width: Int, height: Int) -> [UInt8] {
        if width == templateWidth, height == templateHeight {
            return templatePixels
        }

        var output = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let sourceY = (Double(y) + 0.5) * Double(templateHeight) / Double(height) - 0.5
            let y0 = max(0, min(templateHeight - 1, Int(floor(sourceY))))
            let y1 = min(templateHeight - 1, y0 + 1)
            let fy = max(0, min(1, sourceY - Double(y0)))
            for x in 0..<width {
                let sourceX = (Double(x) + 0.5) * Double(templateWidth) / Double(width) - 0.5
                let x0 = max(0, min(templateWidth - 1, Int(floor(sourceX))))
                let x1 = min(templateWidth - 1, x0 + 1)
                let fx = max(0, min(1, sourceX - Double(x0)))

                let top = Double(templatePixels[y0 * templateWidth + x0]) * (1 - fx)
                    + Double(templatePixels[y0 * templateWidth + x1]) * fx
                let bottom = Double(templatePixels[y1 * templateWidth + x0]) * (1 - fx)
                    + Double(templatePixels[y1 * templateWidth + x1]) * fx
                output[y * width + x] = UInt8(max(0, min(255, top * (1 - fy) + bottom * fy)).rounded())
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
        var verticallyFlippedNumerator = 0.0
        var imageDenom = 0.0
        var templateDenom = 0.0

        for ty in 0..<templateHeight {
            let imageRow = (originY + ty) * imageWidth + originX
            let templateRow = ty * templateWidth
            let flippedTemplateRow = (templateHeight - 1 - ty) * templateWidth
            for tx in 0..<templateWidth {
                let imageDelta = Double(image[imageRow + tx]) - imageMean
                let templateDelta = Double(template[templateRow + tx]) - templateMean
                let flippedTemplateDelta = Double(template[flippedTemplateRow + tx]) - templateMean
                numerator += imageDelta * templateDelta
                verticallyFlippedNumerator += imageDelta * flippedTemplateDelta
                imageDenom += imageDelta * imageDelta
                templateDenom += templateDelta * templateDelta
            }
        }

        let denominator = sqrt(imageDenom * templateDenom)
        guard denominator > 1 else { return -1 }
        // The bundled template was captured in dark mode. In light mode the
        // icon/background contrast is inverted, producing the same shape with
        // a negative correlation.
        return max(
            abs(numerator / denominator),
            abs(verticallyFlippedNumerator / denominator)
        )
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
