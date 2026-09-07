import CoreGraphics
import Foundation

enum ImageDiff {
    static func ratio(_ a: CGImage?, _ b: CGImage?) -> Double {
        guard let a, let b,
              let left = lumaPixels(a, width: 96, height: 56),
              let right = lumaPixels(b, width: 96, height: 56) else {
            return 1
        }

        var sum = 0
        for index in left.indices {
            sum += abs(Int(left[index]) - Int(right[index]))
        }
        return Double(sum) / (Double(left.count) * 255)
    }

    static func fingerprint(_ image: CGImage?) -> String {
        guard let image, let pixels = lumaPixels(image, width: 8, height: 8) else {
            return "none"
        }
        let hash = pixels.reduce(into: 0) { partial, value in
            partial = (partial &* 33) &+ Int(value)
        }
        return String(format: "%08x", hash & 0xFFFF_FFFF)
    }

    private static func lumaPixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let success = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? pixels : nil
    }
}
