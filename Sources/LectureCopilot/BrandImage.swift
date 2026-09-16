import AppKit

enum BrandImage {
    static func menuBarIcon() -> NSImage? {
        imageWithSize(namedPNG("StatusIcon") ?? namedICNS(), NSSize(width: 18, height: 18))
    }

    static func hudLogo() -> NSImage? {
        imageWithSize(namedPNG("HUDIcon") ?? namedPNG("StatusIcon") ?? namedICNS(), NSSize(width: 38, height: 38))
    }

    private static func namedPNG(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func namedICNS() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: "AppIcon")
    }

    private static func imageWithSize(_ image: NSImage?, _ size: NSSize) -> NSImage? {
        guard let image else { return nil }
        let copy = image.copy() as? NSImage ?? image
        copy.size = size
        copy.isTemplate = false
        return copy
    }
}
