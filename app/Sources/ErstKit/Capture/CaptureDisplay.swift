import CoreGraphics
import Foundation

/// Chooses the display a capture stream follows.
enum CaptureDisplay {
    /// Whether more than one display is active.
    ///
    /// Following the focused window costs an Accessibility query or a full window list scan.
    /// With one display there is nothing to follow, so the stream can skip that on every tick.
    static func hasMultiple() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return true }
        return count > 1
    }

    /// The display under the pointer, or the main display when no screen holds the pointer.
    static func underPointer() -> CGDirectDisplayID {
        guard let pointer = CGEvent(source: nil)?.location else {
            return CGMainDisplayID()
        }
        var displayID = CGMainDisplayID()
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(pointer, 1, &displayID, &count)
        guard result == .success, count > 0 else { return CGMainDisplayID() }
        return displayID
    }
}
