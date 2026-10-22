import AppKit
import ApplicationServices
import CoreGraphics

/// Locates the focused window in Quartz's global top-left coordinate space.
enum ActiveDisplay {
    static func currentID() async -> CGDirectDisplayID? {
        guard let processID = await frontmostProcessID(),
            let frame = focusedWindowFrame(processID: processID)
        else { return nil }
        let maximumDisplayCount: UInt32 = 32
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(maximumDisplayCount))
        var count: UInt32 = 0
        guard CGGetDisplaysWithRect(frame, maximumDisplayCount, &displays, &count) == .success else {
            return nil
        }
        return displays.prefix(Int(count)).max { left, right in
            intersectionArea(frame, CGDisplayBounds(left)) < intersectionArea(frame, CGDisplayBounds(right))
        }
    }

    @MainActor
    private static func frontmostProcessID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private static func focusedWindowFrame(processID: pid_t) -> CGRect? {
        if AccessibilityReader.isTrusted() {
            let application = AccessibilityReader.application(processID: processID)
            if let window = AccessibilityReader.focusedWindow(of: application),
                let frame = accessibilityFrame(window), !frame.isEmpty
            {
                return frame
            }
        }
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
                as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == processID,
                window[kCGWindowLayer as String] as? Int == 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds), !frame.isEmpty
            else { continue }
            return frame
        }
        return nil
    }

    private static func accessibilityFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = AccessibilityReader.attribute(kAXPositionAttribute as CFString, of: window),
            let size = AccessibilityReader.attribute(kAXSizeAttribute as CFString, of: window),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
            AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private static func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
