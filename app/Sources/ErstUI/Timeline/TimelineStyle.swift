import AppKit
import SwiftUI

/// Timeline colors and type, from the Timeline section of the design.
enum TimelineStyle {
    static let surfaceTint = Color(hex: 0x18181A).opacity(0.62)
    static let surfaceTintFallback = Color(hex: 0x1A1A1C)
    static let searchTint = Color(hex: 0x1C1C1E).opacity(0.55)
    static let searchTintFallback = Color(hex: 0x232325)
    static let innerHairline = Color.white.opacity(0.141)
    /// Over the frame while search is open from the capsule.
    static let searchDim = Color.black.opacity(0.42)

    static let chipFill = Color.white.opacity(0.059)
    static let chipSelectedFill = Color.erstButter.opacity(0.14)
    static let chipName = Color(hex: 0xE6E2D9)
    static let chipDetail = Color.white.opacity(0.52)
    static let chipDetailSelected = Color.erstButter.opacity(0.7)
    static let pauseLabel = Color(hex: 0x8E8B84)
    static let stripe = Color.white.opacity(0.07)
    static let hourLabel = Color(hex: 0x7E7B74)
    static let heatQuiet = Color(hex: 0x2A2A2D)
    static let monogramFill = Color(hex: 0x2C2C2E)
    static let monogramText = Color(hex: 0xF4F2EE)

    static let actionsFill = Color.white.opacity(0.078)
    static let actionGlyph = Color(hex: 0xF2EFE8)
    static let scaleFill = Color.white.opacity(0.059)
    static let scalePill = Color.white.opacity(0.141)
    static let scaleText = Color.white.opacity(0.6)
    static let placeholder = Color.white.opacity(0.72)
    static let shortcut = Color.white.opacity(0.5)
    static let playheadRing = Color(hex: 0x141416).opacity(0.9)
}

/// The text styles the timeline adds on top of the shared typography scale.
enum TimelineType {
    private static let regular = "SchibstedGrotesk-Regular"
    private static let medium = "SchibstedGrotesk-Regular_Medium"
    static let semiboldFontName = "SchibstedGrotesk-Regular_SemiBold"

    static let sourceTitle = style(14, semiboldFontName)
    static let sourceSubtitle = style(12, regular)
    static let clock = style(24, medium, trackingEm: -0.01)
    static let date = style(13, regular)
    static let placeholder = style(15, regular)
    static let shortcut = style(13, regular)
    static let scale = style(12, regular)
    static let scaleSelected = style(12, medium)
    static let now = style(13, semiboldFontName)

    static func appKitFont(size: CGFloat, weight: Font.Weight) -> NSFont {
        Typography.registerFonts()
        let name =
            switch weight {
            case .semibold, .bold, .heavy, .black: semiboldFontName
            case .medium: medium
            default: regular
            }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }

    private static func style(
        _ size: CGFloat, _ name: String, trackingEm: CGFloat = 0
    ) -> ErstTextStyle {
        Typography.registerFonts()
        return ErstTextStyle(
            font: Font.custom(name, fixedSize: size), tracking: size * trackingEm)
    }
}

/// AppKit mirrors of the timeline colors and fonts for the Core Graphics track.
@MainActor
enum TimelineTrackStyle {
    static let chipNameFont = TimelineType.appKitFont(
        size: TimelineMetrics.chipNameFontSize, weight: .medium)
    static let chipNameSelectedFont = TimelineType.appKitFont(
        size: TimelineMetrics.chipNameFontSize, weight: .semibold)
    static let chipDetailFont = TimelineType.appKitFont(
        size: TimelineMetrics.chipDetailFontSize, weight: .regular)
    static let sessionFont = TimelineType.appKitFont(
        size: TimelineMetrics.chipDetailFontSize, weight: .regular)
    static let hourFont = TimelineType.appKitFont(size: 11, weight: .regular)

    static let chipFill = color(TimelineStyle.chipFill)
    static let chipSelectedFill = color(TimelineStyle.chipSelectedFill)
    static let chipName = color(TimelineStyle.chipName)
    static let chipDetail = color(TimelineStyle.chipDetail)
    static let chipDetailSelected = color(TimelineStyle.chipDetailSelected)
    static let pauseLabel = color(TimelineStyle.pauseLabel)
    static let stripe = color(TimelineStyle.stripe)
    static let hourLabel = color(TimelineStyle.hourLabel)
    static let butter = color(Color.erstButter)
    static let monthColumnSelected = NSColor.white.withAlphaComponent(0.08)
    static let monthColumnHover = NSColor.white.withAlphaComponent(0.05)
    static let monthHoverRing = NSColor.white.withAlphaComponent(0.45)
    /// Under the cursor's butter line, so it reads on butter heat too, like the playhead knob.
    static let monthCursorOutline = color(TimelineStyle.playheadRing)
    static let monthFuture = color(TimelineStyle.heatQuiet).withAlphaComponent(
        TimelineMetrics.monthFutureOpacity)
    static let monthWeekendLabel = color(TimelineStyle.hourLabel).withAlphaComponent(0.55)
    static let monthDaySelectedFont = TimelineType.appKitFont(size: 11, weight: .semibold)
    /// The heat level colors, quietest first, one per level from quiet to busy.
    static let heatLevels: [NSColor] = [
        color(TimelineStyle.heatQuiet), color(.erstHeatOne), color(.erstHeatTwo),
        color(.erstCoral), color(.erstOrange), color(.erstButter),
    ]

    static var chipNameAttributes: [NSAttributedString.Key: Any] {
        attributes(font: chipNameFont, color: chipName)
    }

    static var chipNameSelectedAttributes: [NSAttributedString.Key: Any] {
        attributes(font: chipNameSelectedFont, color: butter)
    }

    static var chipDetailAttributes: [NSAttributedString.Key: Any] {
        attributes(font: chipDetailFont, color: chipDetail)
    }

    static var chipDetailSelectedAttributes: [NSAttributedString.Key: Any] {
        attributes(font: chipDetailFont, color: chipDetailSelected)
    }

    static var sessionAttributes: [NSAttributedString.Key: Any] {
        attributes(font: sessionFont, color: pauseLabel)
    }

    static var hourAttributes: [NSAttributedString.Key: Any] {
        attributes(font: hourFont, color: hourLabel)
    }

    static func monthDayAttributes(isSelected: Bool, isToday: Bool, isWeekend: Bool)
        -> [NSAttributedString.Key: Any]
    {
        if isSelected { return attributes(font: monthDaySelectedFont, color: butter) }
        if isToday { return attributes(font: hourFont, color: chipName) }
        return attributes(font: hourFont, color: isWeekend ? monthWeekendLabel : hourLabel)
    }

    private static func attributes(
        font: NSFont, color: NSColor
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private static func color(_ color: Color) -> NSColor {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return resolved
    }
}

/// Locale-stable strings for the timeline so snapshots read the same.
@MainActor
enum TimelineFormat {
    private static let clockFormatter = formatter("HH:mm:ss")
    private static let dateFormatter = formatter("EEEE, d MMM")
    private static let monthTitleFormatter = formatter("MMMM yyyy")
    private static let monthCursorFormatter = formatter("EEEE d, HH:00")

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func monthTitle(_ date: Date) -> String {
        monthTitleFormatter.string(from: date)
    }

    static func monthCursor(_ date: Date) -> String {
        monthCursorFormatter.string(from: date)
    }

    static func hourText(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: Surfaces

extension View {
    /// The floating dock: native glass tinted for the frame behind it, with its own lift.
    func timelineDockSurface() -> some View {
        modifier(
            TimelineGlassModifier(
                cornerRadius: TimelineMetrics.dockCornerRadius,
                tint: TimelineStyle.surfaceTint,
                fallback: TimelineStyle.surfaceTintFallback,
                shadowRadius: TimelineMetrics.dockShadowRadius,
                shadowY: TimelineMetrics.dockShadowY,
                shadowOpacity: TimelineMetrics.dockShadowOpacity
            ))
    }

    /// The search capsule: native glass tinted slightly lighter than the dock.
    func timelineSearchSurface() -> some View {
        modifier(
            TimelineGlassModifier(
                cornerRadius: TimelineMetrics.searchCornerRadius,
                tint: TimelineStyle.searchTint,
                fallback: TimelineStyle.searchTintFallback,
                shadowRadius: TimelineMetrics.searchShadowRadius,
                shadowY: TimelineMetrics.searchShadowY,
                shadowOpacity: TimelineMetrics.searchShadowOpacity
            ))
    }
}

/// Native glass with the timeline's tint, inner hairline, and lift. The search morph drives it
/// with values between the capsule's and the dock's.
struct TimelineGlassModifier: ViewModifier {
    @Environment(\.erstOpaquePanels) private var opaquePanels
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let tint: Color
    let fallback: Color
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let shadowOpacity: Double

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// A stroke on a surface this round leaves a hairline sliver at each end, so the
    /// overlay clips its stroke to the shape, the same way ErstCapsuleModifier does.
    private var surfaceBorder: some View {
        shape.strokeBorder(TimelineStyle.innerHairline, lineWidth: ControlMetrics.hairlinePoints)
            .clipShape(shape)
    }

    func body(content: Content) -> some View {
        decorated(content: content)
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    @ViewBuilder
    private func decorated(content: Content) -> some View {
        if opaquePanels {
            content
                .clipShape(shape)
                .background(fallback, in: shape)
                .overlay { surfaceBorder }
        } else if reduceTransparency {
            content
                .clipShape(shape)
                .background(.regularMaterial, in: shape)
                .background(tint, in: shape)
                .overlay { surfaceBorder }
        } else {
            content
                .clipShape(shape)
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay { surfaceBorder }
        }
    }
}
