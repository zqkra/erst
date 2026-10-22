import Carbon
import Foundation

/// A global keyboard shortcut described by a virtual key code and modifier flags.
public struct HotKeyShortcut: Sendable, Hashable {
    /// The virtual key code, for example `49` for Space.
    public let keyCode: UInt32
    /// Carbon modifier flags such as `cmdKey` and `shiftKey`.
    public let modifiers: UInt32

    /// Creates a shortcut from a virtual key code and Carbon modifier flags.
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
