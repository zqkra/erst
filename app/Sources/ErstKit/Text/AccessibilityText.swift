import ApplicationServices
import CoreGraphics
import Foundation
import os

private let accessibilityTextLog = Logger(
    subsystem: "app.erst.Erst", category: "AccessibilityText")

/// What one read of the focused window returned, with the numbers the probe reports.
struct AccessibilityReading: Sendable {
    static let empty = AccessibilityReading(lines: [], nodes: 0, milliseconds: 0, truncated: false)
    let lines: [RecognizedLine]
    let nodes: Int
    let milliseconds: Double
    /// True when a limit stopped the walk before it saw every visible element.
    let truncated: Bool
}

/// Reads the visible text of the focused window through the Accessibility API.
///
/// The walk runs on its own serial queue, because every Accessibility call blocks until the
/// target app answers or the messaging timeout passes.
final class AccessibilityTextReader: Sendable {
    /// Elements one walk visits at most. A window with more is a canvas or a huge document.
    static let maxNodes = 3000
    /// Levels one walk descends at most. Deeper elements repeat what their ancestors carry.
    static let maxDepth = 48
    /// Time one read may spend, so a slow app cannot hold a kept frame's text back.
    static let budget = Duration.milliseconds(150)
    /// Characters one line may keep. A longer line is cut at a word boundary.
    static let maxCharacters = 2000

    /// Erst's own bundle prefix. Its windows are never read.
    private static let ownBundlePrefix = "app.erst."

    private let queue = DispatchQueue(label: "app.erst.Erst.accessibilityText")
    private let preparedProcesses = OSAllocatedUnfairLock(initialState: Set<pid_t>())
    private static let reportedTruncation = OSAllocatedUnfairLock(initialState: false)

    /// Reads the focused window of a focus context, on the reader's serial queue.
    func read(_ focus: FocusContext, displayID: CGDirectDisplayID) async -> AccessibilityReading {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.walk(focus, displayID: displayID))
            }
        }
    }

    private func walk(_ focus: FocusContext, displayID: CGDirectDisplayID) -> AccessibilityReading {
        guard AXIsProcessTrusted(), !Self.isOwn(bundleID: focus.bundleID) else { return .empty }
        let start = ContinuousClock.now
        let application = AXUIElementCreateApplication(focus.processID)
        AXUIElementSetMessagingTimeout(application, AccessibilityElement.messageTimeoutSeconds)
        prepare(application, processID: focus.processID)
        guard
            let windowElement = AccessibilityElement.element(
                kAXFocusedWindowAttribute, of: application),
            let window = AccessibilityElement.read(windowElement),
            let windowFrame = window.frame
        else { return .empty }
        let display = CGDisplayBounds(displayID)
        let visible = windowFrame.intersection(display)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return .empty }
        var walk = AccessibilityWalk(
            root: window.element,
            visibleRect: visible,
            displayBounds: display,
            deadline: start.advanced(by: Self.budget)
        )
        walk.run()
        let milliseconds = Self.milliseconds(since: start)
        if walk.truncated { Self.logTruncation(nodes: walk.nodes, milliseconds: milliseconds) }
        return AccessibilityReading(
            lines: walk.lines,
            nodes: walk.nodes,
            milliseconds: milliseconds,
            truncated: walk.truncated
        )
    }

    /// Makes an Electron or Chromium app build its accessibility tree, once per process.
    private func prepare(_ application: AXUIElement, processID: pid_t) {
        let isFirstRead = preparedProcesses.withLock { prepared in
            prepared.insert(processID).inserted
        }
        guard isFirstRead else { return }
        // No AXEnhancedUserInterface: it changes how some apps animate window moves.
        _ = AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Trims the text, collapses whitespace into one space, and cuts it at a word boundary.
    ///
    /// `wasCut` says the text lost its tail, so its box no longer covers only what it holds.
    static func normalize(_ text: String) -> (text: String, wasCut: Bool) {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > maxCharacters else { return (collapsed, false) }
        let cut = collapsed.prefix(maxCharacters)
        guard let boundary = cut.lastIndex(of: " ") else { return (String(cut), true) }
        return (String(cut[..<boundary]), true)
    }

    /// Whether a bundle identifier belongs to Erst itself.
    private static func isOwn(bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier || bundleID.hasPrefix(ownBundlePrefix)
    }

    /// Logs the first truncated walk of the process, at debug, with the numbers that explain it.
    private static func logTruncation(nodes: Int, milliseconds: Double) {
        let isFirst = reportedTruncation.withLock { reported in
            defer { reported = true }
            return !reported
        }
        guard isFirst else { return }
        let timing = String(format: "%.0f", milliseconds)
        let message =
            "Accessibility text read stopped at a limit after \(timing) ms and \(nodes) elements"
        accessibilityTextLog.debug("\(message, privacy: .public)")
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: ContinuousClock.now)
        return Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}

/// One depth-first pass over a window's accessibility tree, with the reading limits applied.
private struct AccessibilityWalk {
    let visibleRect: CGRect
    let displayBounds: CGRect
    let deadline: ContinuousClock.Instant
    private(set) var lines: [RecognizedLine] = []
    private(set) var nodes = 0
    private(set) var truncated = false
    private var seen: Set<LineKey> = []
    private var stack: [(element: AXUIElement, depth: Int)]

    init(
        root: AXUIElement, visibleRect: CGRect, displayBounds: CGRect,
        deadline: ContinuousClock.Instant
    ) {
        self.visibleRect = visibleRect
        self.displayBounds = displayBounds
        self.deadline = deadline
        self.stack = [(root, 0)]
    }

    mutating func run() {
        while let (element, depth) = stack.popLast() {
            if ContinuousClock.now >= deadline || nodes >= AccessibilityTextReader.maxNodes {
                truncated = true
                return
            }
            nodes += 1
            guard let snapshot = AccessibilityElement.read(element),
                let children = inspect(snapshot, depth: depth)
            else { continue }
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
    }

    /// Reads the element's own text and answers the children to walk, or nil to skip its subtree.
    private mutating func inspect(_ snapshot: AccessibilityElement, depth: Int) -> [AXUIElement]? {
        guard !snapshot.isSecure, !snapshot.isHidden else { return nil }
        if let frame = snapshot.frame, !frame.intersects(visibleRect) { return nil }
        readText(of: snapshot)
        guard depth + 1 < AccessibilityTextReader.maxDepth else {
            if !snapshot.children.isEmpty { truncated = true }
            return nil
        }
        return snapshot.children
    }

    private mutating func readText(of snapshot: AccessibilityElement) {
        if let text = snapshot.text {
            append(text, in: snapshot.frame)
        } else if snapshot.isTextArea {
            appendTextArea(snapshot)
        } else if let caption = snapshot.caption {
            append(caption, in: snapshot.frame)
        }
    }

    /// Splits the visible part of a text area into one estimated box per line.
    private mutating func appendTextArea(_ snapshot: AccessibilityElement) {
        guard let visible = snapshot.frame?.intersection(visibleRect), !visible.isEmpty else {
            return
        }
        let text = snapshot.visibleText(deadline: deadline)
        if text.truncated { truncated = true }
        guard !text.lines.isEmpty else { return }
        let height = visible.height / CGFloat(text.lines.count)
        for (index, line) in text.lines.enumerated() {
            let frame = CGRect(
                x: visible.minX, y: visible.minY + CGFloat(index) * height,
                width: visible.width, height: height)
            append(line, in: frame, isExact: false)
        }
    }

    private mutating func append(_ text: String, in frame: CGRect?, isExact: Bool = true) {
        guard let frame, let box = box(for: frame) else { return }
        let normalized = AccessibilityTextReader.normalize(text)
        guard !normalized.text.isEmpty else { return }
        if normalized.wasCut { truncated = true }
        let line = RecognizedLine(
            text: normalized.text, box: box, source: .accessibility,
            boxIsExact: isExact && !normalized.wasCut)
        guard seen.insert(LineKey(text: line.text, box: line.box)).inserted else { return }
        lines.append(line)
    }

    /// Text shorter than this is not readable. Collapsed menus, hidden panels, and rows scrolled
    /// almost out of view report frames this thin.
    private static let minimumLineHeightPoints: CGFloat = 4

    /// Normalizes a global top-left frame to the display and clips it to the visible part, or nil
    /// when too little of it shows to read.
    private func box(for frame: CGRect) -> CGRect? {
        let visible = frame.intersection(visibleRect)
        guard !visible.isNull, visible.width > 0, visible.height >= Self.minimumLineHeightPoints,
            displayBounds.width > 0, displayBounds.height > 0
        else { return nil }
        let box = CGRect(
            x: (visible.minX - displayBounds.minX) / displayBounds.width,
            y: (visible.minY - displayBounds.minY) / displayBounds.height,
            width: visible.width / displayBounds.width,
            height: visible.height / displayBounds.height
        )
        guard box.width > 0, box.height > 0 else { return nil }
        return box
    }
}

/// The text and box that make two reads of one element the same line.
private struct LineKey: Hashable {
    let text: String
    let box: CGRect
}
