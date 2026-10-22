import CoreGraphics
import ErstModel
import ErstUI

/// How recognized text reads in a Moment: paragraphs, lists, entries with values, and the noise
/// the accessibility tree adds.
enum ReadingBlocksContract {
    static func verify() throws {
        try paragraphsAndSidebar()
        try listWithValues()
    }

    /// Sentences, a sidebar, and a row of a name with its handle.
    private static func paragraphsAndSidebar() throws {
        let lineHeight = 0.02
        func line(_ text: String, x: Double, y: Double, width: Double) -> TextLine {
            TextLine(text: text, box: CGRect(x: x, y: y, width: width, height: lineHeight))
        }
        let lines = [
            line("The design system is live. Spacing,", x: 0.2, y: 0.10, width: 0.3),
            line("Maya Chen", x: 0.2, y: 0.07, width: 0.08),
            line("@mayachen", x: 0.3, y: 0.07, width: 0.08),
            line("type, and color live in one time-", x: 0.2, y: 0.125, width: 0.3),
            line("line.", x: 0.2, y: 0.15, width: 0.05),
            line("Explore", x: 0.0, y: 0.14, width: 0.05),
            line("Home", x: 0.0, y: 0.10, width: 0.04),
            line("Messages", x: 0.0, y: 0.18, width: 0.05),
            line("Settings", x: 0.0, y: 0.30, width: 0.05),
            TextLine(text: "36.4K posts", box: CGRect(x: 0.0, y: 0.325, width: 0.04, height: 0.014)),
        ]
        let expected: [ReadingBlock] = [
            .items(["Home", "Explore", "Messages"]),
            .text([ReadingLine("Settings"), ReadingLine("36.4K posts", isDetail: true)]),
            .text([
                ReadingLine("Maya Chen  @mayachen", isDetail: true),
                ReadingLine("The design system is live. Spacing, type, and color live in one time-line."),
            ]),
        ]
        try require(
            lines.readingBlocks == expected,
            "Recognized text must read as blocks: \(lines.readingBlocks)")
    }

    /// A streaming site's sidebar from a real frame (coordinates in ten-thousandths of the screen):
    /// channel names with viewer counts on the right and a category under each name, under a
    /// toolbar that spans the sidebar and its counts. A hidden menu item one pixel tall, and a
    /// count read one element per character, come from the accessibility tree.
    private static func listWithValues() throws {
        func line(_ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> TextLine {
            TextLine(
                text: text,
                box: CGRect(x: x / 10_000, y: y / 10_000, width: width / 10_000, height: height / 10_000))
        }
        let lines = [
            line("Tab groups Tools YT resources", 23, 444, 2700, 194),
            line("Siguiendo", 86, 2889, 305, 146),
            line("Westcol", 242, 3153, 219, 125),
            line("96,3 mil", 734, 3167, 211, 125),
            line("Conversando", 242, 3299, 348, 125),
            line("RDjavi", 242, 3514, 172, 125),
            line("12,2 mil", 742, 3528, 203, 125),
            line("Configuración del chat", 300, 3600, 688, 7),
            line("Scam With Your Friends", 242, 3660, 441, 125),
            line("LACOBRAAA", 242, 3875, 352, 125),
            line("7 mil", 820, 3889, 125, 125),
            line("Conversando", 242, 4021, 348, 125),
            line("Mostrar más", 63, 4979, 379, 139),
            line("9", 7598, 9299, 39, 125),
            line("6", 7633, 9299, 39, 125),
            line(".", 7668, 9299, 16, 125),
            line("3", 7680, 9299, 43, 125),
            line("2", 7719, 9299, 39, 125),
            line("3", 7754, 9299, 39, 125),
            line("espectadores", 7805, 9299, 367, 125),
        ]
        let expected: [ReadingBlock] = [
            .text([ReadingLine("Tab groups Tools YT resources")]),
            .text([ReadingLine("Siguiendo")]),
            .entries([
                ReadingEntry("Westcol", value: "96,3 mil", details: ["Conversando"]),
                ReadingEntry("RDjavi", value: "12,2 mil", details: ["Scam With Your Friends"]),
                ReadingEntry("LACOBRAAA", value: "7 mil", details: ["Conversando"]),
            ]),
            .text([ReadingLine("Mostrar más")]),
            .text([ReadingLine("96.323 espectadores")]),
        ]
        try require(
            lines.readingBlocks == expected,
            "A list with values must read as entries: \(lines.readingBlocks)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SnapshotError.contract(message) }
    }
}
