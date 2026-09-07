import ApplicationServices
import CoreGraphics
import Foundation

enum AXAccess {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as AnyObject?
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func role(_ element: AXUIElement) -> String {
        string(element, kAXRoleAttribute) ?? ""
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        children(app).filter { role($0) == (kAXWindowRole as String) }
    }

    static func menuBar(of app: AXUIElement) -> AXUIElement? {
        children(app).first { role($0) == (kAXMenuBarRole as String) }
    }

    static func menuBarItem(named titles: [String], in app: AXUIElement) -> AXUIElement? {
        guard let bar = menuBar(of: app) else { return nil }
        return children(bar).first { element in
            titles.contains { label(element).localizedCaseInsensitiveContains($0) }
        }
    }

    static func menuItem(named titles: [String], inMenuBarItem barItem: AXUIElement) -> AXUIElement? {
        for child in children(barItem) {
            let items = role(child) == (kAXMenuRole as String) ? children(child) : [child]
            if let match = items.first(where: { element in
                role(element) == (kAXMenuItemRole as String)
                    && titles.contains { label(element).localizedCaseInsensitiveContains($0) }
            }) {
                return match
            }
        }
        return nil
    }

    static func label(_ element: AXUIElement) -> String {
        [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXIdentifierAttribute,
            kAXPlaceholderValueAttribute
        ]
        .compactMap { string(element, $0) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        return settable.boolValue
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    static func setValue(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    static func setFocused(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func find(_ root: AXUIElement, depth: Int = 0, maxDepth: Int = 20, match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(root) {
            return root
        }
        guard depth < maxDepth else { return nil }
        for child in children(root) {
            if let found = find(child, depth: depth + 1, maxDepth: maxDepth, match: match) {
                return found
            }
        }
        return nil
    }

    static func collect(_ root: AXUIElement, depth: Int = 0, maxDepth: Int = 20, into result: inout [AXUIElement], match: (AXUIElement) -> Bool) {
        if match(root) {
            result.append(root)
        }
        guard depth < maxDepth else { return }
        for child in children(root) {
            collect(child, depth: depth + 1, maxDepth: maxDepth, into: &result, match: match)
        }
    }

    static func dump(_ root: AXUIElement, depth: Int = 0, maxDepth: Int = 12, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let value = string(root, kAXValueAttribute).map { String($0.prefix(80)) } ?? ""
        let settable = isSettable(root, kAXValueAttribute) ? "settable" : ""
        let actionList = actions(root).joined(separator: ",")
        lines.append("\(indent)role=\(role(root)) label=\(label(root)) \(settable) actions=\(actionList) value=\(value)")
        guard depth < maxDepth else { return }
        for child in children(root) {
            dump(child, depth: depth + 1, maxDepth: maxDepth, into: &lines)
        }
    }

    static func waitUntil(timeout: TimeInterval, interval: TimeInterval = 0.05, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: interval)
        }
        return false
    }
}
