import ApplicationServices
import Foundation

/// Best effort reads of the focused window and browser URL through the Accessibility API.
enum AccessibilityReader {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func application(processID: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(processID)
    }

    static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        element(from: attribute(kAXFocusedWindowAttribute as CFString, of: application))
    }

    static func focusedElement(of application: AXUIElement) -> AXUIElement? {
        element(from: attribute(kAXFocusedUIElementAttribute as CFString, of: application))
    }

    static func title(of element: AXUIElement) -> String? {
        attribute(kAXTitleAttribute as CFString, of: element) as? String
    }

    static func browserURL(from root: AXUIElement) -> URL? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(150))
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var visited = 0
        while index < queue.count, visited < 400, clock.now < deadline {
            let (element, depth) = queue[index]
            index += 1
            visited += 1
            if let role = attribute(kAXRoleAttribute as CFString, of: element) as? String,
                role == "AXWebArea",
                let rawURL = attribute(kAXURLAttribute as CFString, of: element),
                let url = url(from: rawURL)
            {
                return url
            }
            guard depth < 12,
                let children = attribute(kAXChildrenAttribute as CFString, of: element)
                    as? [AXUIElement]
            else { continue }
            for child in children {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    static func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success else { return nil }
        return value
    }

    private static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func url(from value: CFTypeRef) -> URL? {
        if let url = value as? URL {
            return url
        }
        if let url = value as? NSURL {
            return url as URL
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }
}
