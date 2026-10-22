import AppKit
import SwiftUI

/// The design tokens from docs/DESIGN.md.
public enum Radius {
    public static let window: CGFloat = 26
    public static let panel: CGFloat = 30
    public static let group: CGFloat = 18
    public static let frame: CGFloat = 22
    public static let inspector: CGFloat = 26
    public static let card: CGFloat = 16
    public static let segment: CGFloat = 11
    public static let icon: CGFloat = 7
    public static let row: CGFloat = 6
    public static let badge: CGFloat = 3
    public static let thumbnail: CGFloat = 8
    public static let bar: CGFloat = 6
    public static let control: CGFloat = 999
}

/// The only spacing steps views may use.
public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 20
    public static let xxLarge: CGFloat = 24
    public static let xxxLarge: CGFloat = 32
    public static let huge: CGFloat = 44
}

extension Color {
    public static let erstGround = Color(hex: 0x0E0E0F)
    public static let erstText = Color(hex: 0xF4F2EE)
    public static let erstSecondary = Color(hex: 0x9B988F)
    public static let erstButter = Color(hex: 0xF8D677)
    public static let erstOrange = Color(hex: 0xF6A563)
    public static let erstCoral = Color(hex: 0xEF7A68)
    public static let erstInk = Color(hex: 0x1A1A1A)
    public static let erstSurface = Color.erstText.opacity(0.045)
    public static let erstDisabledFill = Color.white.opacity(0.08)
    public static let erstHairline = Color.erstText.opacity(0.09)
    public static let erstTrack = Color(hex: 0x3A302C)
    public static let erstHeatOne = Color(hex: 0x5A3330)
    public static let erstHeatTwo = Color(hex: 0xB8574A)
    public static let erstScrim = Color.black.opacity(0.48)
    public static let erstFrameDim = Color.black.opacity(0.1)
    public static let erstFrameBackdrop = Color.black.opacity(0.52)
    public static let erstControlScrim = Color.black.opacity(0.28)
    public static let erstSelection = Color.erstButter.opacity(0.18)
    public static let erstStorageText = Color.erstButter.opacity(0.55)
    public static let erstStoragePreviews = Color.erstButter.opacity(0.3)
    public static let erstIconPlaceholder = Color.erstSecondary.opacity(0.22)
    /// A menu row under the pointer or the keyboard, neutral like Control Center's menus.
    public static let erstRowHighlight = Color.erstText.opacity(0.1)
    public static let erstRowPressed = Color.erstText.opacity(0.16)
    /// Long recognized text, a step quieter than headings so a page of it does not shout.
    public static let erstReadingText = Color.erstText.opacity(0.8)
    /// A highlighter stroke over matched text on a captured frame.
    public static let erstMatchMark = Color.erstButter.opacity(0.4)
    /// Behind a matched word inside text.
    public static let erstMatchWash = Color.erstButter.opacity(0.16)
    /// Under a selected card in a grid of results, and a lighter step under the pointer.
    public static let erstCardSelected = Color.erstText.opacity(0.08)
    public static let erstCardHover = Color.erstText.opacity(0.04)

    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

}

/// Shared geometry for small controls and icon shapes.
public enum ControlMetrics {
    public static let hairlinePoints: CGFloat = 1
    public static let circleButtonPoints: CGFloat = 30
    public static let iconCornerFraction: CGFloat = 0.23
    public static let markSizeFraction: CGFloat = 0.56
}

/// Native settings window and form geometry.
public enum SettingsLayout {
    public static let minimumWidth: CGFloat = 900
    public static let minimumHeight: CGFloat = 600
    public static let sidebarMinimumWidth: CGFloat = 190
    public static let sidebarIdealWidth: CGFloat = 200
    public static let sidebarMaximumWidth: CGFloat = 220
    public static let sidebarIconSize: CGFloat = 18
    public static let appIconSize: CGFloat = 20
    public static let aboutIconSize: CGFloat = 64
    public static let storageBarHeight: CGFloat = 10
    public static let storageSwatchSize: CGFloat = 10
    public static let confirmationWidth: CGFloat = 320
    public static let confirmationIconSize: CGFloat = 48
}

/// Menu bar window geometry, after the system's Control Center menus: every line of text starts
/// at `contentInset`, and a highlighted row reaches to `rowInset` from the window edge.
public enum MenuBarLayout {
    public static let width: CGFloat = 320
    public static let rowInset: CGFloat = 6
    public static let contentInset: CGFloat = 16
    public static let rowHeight: CGFloat = 26
    public static let sectionTitleHeight: CGFloat = 24
    public static let separatorGap: CGFloat = 6
    public static let appIconSize: CGFloat = 16
}

/// The tint and lift every floating glass surface shares.
public enum GlassSurface {
    /// A quiet dark tint so Schibsted text stays legible over any wallpaper.
    public static let tint = Color.black.opacity(0.34)
    public static let shadow = Color.black.opacity(0.3)
    public static let shadowRadius: CGFloat = 8
    public static let shadowY: CGFloat = 4
}

/// Heat bar and playhead geometry in points.
public enum HeatMetrics {
    public static let defaultHeight: CGFloat = 48
    public static let gapFraction: CGFloat = 0.26
    public static let minimumGap: CGFloat = 1
    public static let minimumBarWidth: CGFloat = 1.5
    public static let minimumBarHeight: CGFloat = 3
    public static let playheadInset: CGFloat = 1
    public static let playheadWidth: CGFloat = 2
    public static let playheadDiameter: CGFloat = 12
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

private struct ErstOpaquePanelsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Development snapshots cannot composite system glass, so they ask for the solid fallback.
    public var erstOpaquePanels: Bool {
        get { self[ErstOpaquePanelsKey.self] }
        set { self[ErstOpaquePanelsKey.self] = newValue }
    }
}

/// Applies the theme's font and tracking together.
public struct ErstTextStyle: Sendable {
    public let font: Font
    public let tracking: CGFloat

    public init(font: Font, tracking: CGFloat) {
        self.font = font
        self.tracking = tracking
    }
}

extension Text {
    public func erstStyle(_ style: ErstTextStyle) -> Text {
        font(style.font).tracking(style.tracking)
    }
}

/// The floating surface every overlay screen sits on.
public struct ErstGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.erstOpaquePanels) private var opaquePanels
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    public func body(content: Content) -> some View {
        surface(content: content)
            .shadow(
                color: GlassSurface.shadow,
                radius: GlassSurface.shadowRadius,
                x: 0,
                y: GlassSurface.shadowY
            )
    }

    @ViewBuilder
    private func surface(content: Content) -> some View {
        if opaquePanels {
            content
                .clipShape(shape)
                .background(Color.erstGround, in: shape)
                .overlay {
                    shape.strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
                }
        } else if reduceTransparency {
            content
                .clipShape(shape)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
                }
        } else {
            content
                .clipShape(shape)
                .glassEffect(.regular.tint(GlassSurface.tint).interactive(true), in: shape)
        }
    }
}

/// A capsule surface with the same transparency fallback as the panels.
public struct ErstCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.erstOpaquePanels) private var opaquePanels

    private var shape: Capsule {
        Capsule(style: .continuous)
    }

    public func body(content: Content) -> some View {
        if opaquePanels {
            content
                .clipShape(shape)
                .background(Color.erstGround, in: shape)
                .overlay {
                    shape.strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
                        // A stroked capsule leaves a vertical sliver at each end, so the
                        // stroke is clipped to the capsule to keep one even border.
                        .clipShape(shape)
                }
        } else if reduceTransparency {
            content
                .clipShape(shape)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
                        .clipShape(shape)
                }
        } else {
            content
                .clipShape(shape)
                .glassEffect(.regular.tint(GlassSurface.tint).interactive(true), in: shape)
        }
    }
}

/// The native window material for the Activity, Onboarding, and reminder windows.
public struct ErstWindowMaterialModifier: ViewModifier {
    @Environment(\.erstOpaquePanels) private var opaquePanels

    public func body(content: Content) -> some View {
        if opaquePanels {
            content.background(Color.erstGround, ignoresSafeAreaEdges: .all)
        } else {
            content.background(.regularMaterial, ignoresSafeAreaEdges: .all)
        }
    }
}

/// The primary action: butter with ink text, or a quiet fill while disabled.
private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.erstInk : Color.erstSecondary)
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.erstButter : Color.erstDisabledFill)
            }
    }
}

/// The primary action: system glass normally, flat butter when snapshots need the solid fallback.
public struct ProminentActionModifier: ViewModifier {
    @Environment(\.erstOpaquePanels) private var opaquePanels
    @Environment(\.isEnabled) private var isEnabled

    public func body(content: Content) -> some View {
        if opaquePanels || !isEnabled {
            content.buttonStyle(PrimaryActionButtonStyle())
        } else {
            content
                .buttonStyle(.glassProminent)
                .tint(Color.erstButter)
                .foregroundStyle(Color.erstInk)
        }
    }
}

/// A secondary action: system glass normally, a quiet capsule in snapshots.
public struct GlassActionModifier: ViewModifier {
    @Environment(\.erstOpaquePanels) private var opaquePanels

    public func body(content: Content) -> some View {
        if opaquePanels {
            content
                .buttonStyle(.plain)
                .foregroundStyle(Color.erstText)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.erstSurface)
                }
        } else {
            content
                .buttonStyle(.glass)
                .foregroundStyle(Color.erstText)
        }
    }
}

extension View {
    /// Applies the theme's secondary action treatment.
    public func glassAction() -> some View {
        modifier(GlassActionModifier())
    }

    /// Applies the theme's primary action treatment.
    public func prominentAction() -> some View {
        modifier(ProminentActionModifier())
    }

    /// Applies the floating glass surface treatment.
    public func erstGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(ErstGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// Applies the standard capsule treatment.
    public func erstCapsule() -> some View {
        modifier(ErstCapsuleModifier())
    }

    /// Applies the native window material used by secondary windows.
    public func windowMaterial() -> some View {
        modifier(ErstWindowMaterialModifier())
    }
}
