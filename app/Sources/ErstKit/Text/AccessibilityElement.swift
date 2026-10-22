import ApplicationServices
import CoreGraphics
import Foundation

/// One element of the accessibility tree, read in a single IPC call.
///
/// An unsupported attribute comes back as an `AXValue` of type `axError`, which reads as nil.
struct AccessibilityElement {
    /// Roles whose text lives in `AXValue`.
    private static let valueRoles: Set<String> = [
        kAXStaticTextRole, kAXTextFieldRole, kAXComboBoxRole,
    ]
    /// Roles that label themselves through `AXTitle`.
    private static let captionRoles: Set<String> = [
        kAXButtonRole, linkRole, kAXHeadingRole, kAXRadioButtonRole, kAXCheckBoxRole,
        kAXPopUpButtonRole, kAXMenuButtonRole,
    ]
    /// The secure text field role. The SDK exports the subrole only.
    private static let secureTextFieldRole = "AXSecureTextField"
    /// The link role. The SDK exports no constant for it.
    private static let linkRole = "AXLink"
    /// Lines of a text area that are read. Deeper text is left to OCR.
    static let maxTextAreaLines = 200
    /// Messaging timeout set on each element before its read, so a hung app answers as an error
    /// quickly. It applies only to the element it is set on, and every child the API returns is a
    /// new object that starts at the default of about 6 seconds.
    static let messageTimeoutSeconds: Float = 0.05
    /// Time the two visible-range calls can take, reserved before a text area asks for its range.
    static let textAreaCallReserve = Duration.seconds(Double(messageTimeoutSeconds) * 2)

    private enum Attribute: Int {
        case role
        case subrole
        case value
        case title
        case position
        case size
        case hidden
        case children
    }

    /// The attribute names, in the order the multiple-attribute call returns them.
    nonisolated(unsafe) private static let attributes =
        [
            kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXTitleAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXHiddenAttribute, kAXChildrenAttribute,
        ] as CFArray

    let element: AXUIElement
    let role: String
    let subrole: String?
    let frame: CGRect?
    let isHidden: Bool
    let children: [AXUIElement]
    private let valueText: String?
    private let titleText: String?

    /// Reads one element and the attributes the walk needs.
    static func read(_ element: AXUIElement) -> AccessibilityElement? {
        AXUIElementSetMessagingTimeout(element, messageTimeoutSeconds)
        var copied: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, attributes, AXCopyMultipleAttributeOptions(), &copied)
        guard error == .success, let values = copied as? [AnyObject] else { return nil }
        func raw(_ attribute: Attribute) -> CFTypeRef? {
            let index = attribute.rawValue
            guard index < values.count else { return nil }
            let value: CFTypeRef = values[index]
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return value }
            let axValue = unsafeDowncast(value, to: AXValue.self)
            return AXValueGetType(axValue) == .axError ? nil : value
        }
        guard let role = raw(.role) as? String else { return nil }
        return AccessibilityElement(
            element: element,
            role: role,
            subrole: raw(.subrole) as? String,
            frame: frame(position: raw(.position), size: raw(.size)),
            isHidden: raw(.hidden) as? Bool ?? false,
            children: raw(.children) as? [AXUIElement] ?? [],
            valueText: raw(.value) as? String,
            titleText: raw(.title) as? String
        )
    }

    /// Reads one element-valued attribute, such as the focused window of an application.
    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var copied: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &copied) == .success,
            let copied, CFGetTypeID(copied) == AXUIElementGetTypeID()
        else { return nil }
        let child = unsafeDowncast(copied, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(child, messageTimeoutSeconds)
        return child
    }

    /// Whether the element hides a password, so neither it nor its subtree is read.
    var isSecure: Bool {
        role == Self.secureTextFieldRole || subrole == kAXSecureTextFieldSubrole
    }

    /// Whether the element is a text area, whose visible range limits what is read.
    var isTextArea: Bool {
        role == kAXTextAreaRole
    }

    /// Text of a role that carries it in `AXValue`.
    var text: String? {
        Self.valueRoles.contains(role) ? valueText : nil
    }

    /// The title of a role that labels itself, when no child carries the text. The description
    /// is left out: it is the spoken label of an icon, such as "Back" or "Unnamed bookmark", and
    /// not text on screen. A visible label the tree only describes still reaches OCR.
    var caption: String? {
        guard Self.captionRoles.contains(role), children.isEmpty else { return nil }
        return titleText
    }

    /// The on-screen lines of a text area, in order, and whether a limit cut the read.
    ///
    /// Without a visible range the tree does not say what is on screen, so the area contributes
    /// nothing and OCR reads it. The deadline keeps the two range calls from running past the
    /// walk's budget, so a slow app cannot stretch one read.
    func visibleText(deadline: ContinuousClock.Instant) -> (lines: [String], truncated: Bool) {
        guard ContinuousClock.now.advanced(by: Self.textAreaCallReserve) < deadline else {
            return ([], true)
        }
        guard let range = visibleCharacterRange(), let text = string(for: range) else {
            return ([], false)
        }
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (
            Array(lines.prefix(Self.maxTextAreaLines)),
            lines.count > Self.maxTextAreaLines
        )
    }

    /// The character range that is visible inside the text area.
    private func visibleCharacterRange() -> AXValue? {
        var copied: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXVisibleCharacterRangeAttribute as CFString, &copied) == .success,
            let copied, CFGetTypeID(copied) == AXValueGetTypeID()
        else { return nil }
        let range = unsafeDowncast(copied, to: AXValue.self)
        return AXValueGetType(range) == .cfRange ? range : nil
    }

    /// The text of one character range, asked for by parameter so only that part crosses the IPC.
    private func string(for range: AXValue) -> String? {
        var copied: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, range, &copied)
                == .success
        else { return nil }
        return copied as? String
    }

    private static func frame(position: CFTypeRef?, size: CFTypeRef?) -> CGRect? {
        guard let origin = Self.point(from: position), let extent = Self.size(from: size) else {
            return nil
        }
        return CGRect(origin: origin, size: extent)
    }

    private static func point(from reference: CFTypeRef?) -> CGPoint? {
        guard let value = axValue(from: reference), AXValueGetType(value) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(from reference: CFTypeRef?) -> CGSize? {
        guard let value = axValue(from: reference), AXValueGetType(value) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func axValue(from reference: CFTypeRef?) -> AXValue? {
        guard let reference, CFGetTypeID(reference) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(reference, to: AXValue.self)
    }
}
