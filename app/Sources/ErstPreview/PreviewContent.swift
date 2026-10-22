import CoreGraphics
import Foundation

/// How a synthetic preview window is laid out.
enum PreviewLayout: String, Sendable {
    case xFeed
    case whatsApp
    case youtube
    case article
    case mail
    case notes
    case editor

    /// The flat background the app fills its frame with.
    var background: CGColor {
        switch self {
        case .xFeed: PreviewPalette.window
        case .whatsApp: PreviewPalette.whatsAppPage
        case .youtube: PreviewPalette.youtubePage
        case .article, .mail, .notes: PreviewPalette.lightWindow
        case .editor: PreviewPalette.editorPage
        }
    }
}

/// One line of synthetic preview text, positioned in the 1600x1000 frame.
struct PreviewLineSpec {
    let text: String
    let rect: CGRect
}

private let frameWidth: CGFloat = 1600
private let frameHeight: CGFloat = 1000

func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat)
    -> PreviewLineSpec
{
    PreviewLineSpec(
        text: text,
        rect: CGRect(
            x: x / frameWidth, y: y / frameHeight, width: width / frameWidth, height: height / frameHeight)
    )
}

enum PreviewContent {
    static func lines(for layout: PreviewLayout, variant: Int, title: String?) -> [PreviewLineSpec] {
        switch layout {
        case .article: article(variant, title: title)
        case .xFeed: xFeed(variant)
        case .whatsApp: whatsApp(variant)
        case .youtube: youtube(variant)
        case .mail: mail(variant)
        case .notes: notes(variant, title: title)
        case .editor: editor(variant)
        }
    }

    static func article(_ variant: Int, title: String?) -> [PreviewLineSpec] {
        let heading = title ?? "Designing calm software"
        let sidebar = [
            "Reading list", "Design systems", "Local first", "The quiet interface", "Notes on memory",
        ]
        var specs = sidebar.enumerated().map { index, item in
            line(item, 120, 150 + CGFloat(index) * 46, 240, index == 0 ? 20 : 17)
        }
        specs += [
            line(heading, 420, 148, 900, 42),
            line("A field guide for software that stays out of the way", 420, 206, 900, 22),
            line("Maya Chen, 8 min read", 420, 242, 600, 15),
            line("Calm software does not ask for attention. It waits for a question.", 420, 310, 920, 19),
            line("The best interface is one you forget between uses.", 420, 342, 900, 19),
            line(
                "A design system keeps every screen on the same rhythm, so the person",
                420, 374, 930, 19
            ),
            line("never has to learn the same thing twice.", 420, 406, 900, 19),
            line("Motion should explain a change, never decorate it.", 420, 470, 900, 19),
            line("Color means heat. Butter marks what is active.", 420, 502, 900, 19),
            line("Quiet defaults beat loud preferences.", 420, 566, 900, 26),
            line("Most people open a preference once. Make the first answer right.", 420, 606, 920, 19),
            line("Every empty state needs a next action.", 420, 638, 900, 19),
            line("Keep the frame, not the chrome.", 420, 702, 900, 19),
            line("A memory of your screen should feel like a shelf, not a feed.", 420, 734, 940, 19),
            line("Search is a way back, not a way in.", 420, 766, 900, 19),
            line("Design notes, October", 420, 830, 500, 15),
        ]
        let quotes = [
            "The quiet interface leaves room for the work.",
            "Memory is a place you return to, not a list you scroll.",
            "Good software keeps its promises without raising its voice.",
        ]
        specs.append(line(quotes[variant % quotes.count], 1060, 500, 420, 30))
        return specs
    }

    static func youtube(_ variant: Int) -> [PreviewLineSpec] {
        let videos = [
            ("Designing a calmer home screen", "Maya Chen", "18:24"),
            ("A week of local first notes", "Noah Park", "12:08"),
            ("Spacing scales that survive", "Lea Fischer", "24:51"),
            ("Screen memory in practice", "Erst", "09:36"),
            ("The quiet interface", "Maya Chen", "31:12"),
            ("Building the timeline dock", "Noah Park", "16:44"),
        ]
        var specs: [PreviewLineSpec] = [
            line("YouTube", 80, 120, 160, 30),
            line("Search", 700, 126, 160, 18),
        ]
        for (index, video) in videos.enumerated() {
            let column = CGFloat(index % 3)
            let row = CGFloat(index / 3)
            let x = 110 + column * 480
            let top = 210 + row * 330
            specs += [
                line(video.0, x, top + 226, 420, 19),
                line(video.1, x, top + 252, 260, 14),
                line(video.2, x, top + 274, 160, 14),
            ]
        }
        if variant % 2 == 0 {
            specs.append(line("Recommended today", 110, 170, 340, 24))
        } else {
            specs.append(line("Continue watching", 110, 170, 340, 24))
        }
        return specs
    }

}
