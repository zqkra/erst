import CoreGraphics
import Foundation

/// The installer window's background: echoes spread out of the app icon, cooling as they go, and
/// the e's mouth opens toward Applications. The design is "20 Installer · A Echo" in Paper.
public enum InstallerArt {
    public static let size = CGSize(width: 660, height: 400)
    /// Finder centers the icons here, so the echoes start from the app icon's own e.
    public static let appIconCenter = CGPoint(x: 172, y: 177)
    public static let applicationsCenter = CGPoint(x: 484, y: 283)
    public static let iconSizePoints: CGFloat = 128
    public static let caption = "Drag Erst into Applications"
    /// The caption's baseline sits on clean ground, below where the heat fades out.
    public static let captionBaselineY: CGFloat = 381

    private static let echoes = EchoFalloff(
        firstRadius: 114, step: 22.8, count: 16, width: 5.5, coldestHeat: 0.22)
    private static let horizonWidth: CGFloat = 5
    private static let horizonHeat: CGFloat = 0.62

    public static let development = HeatDevelopment(
        blurPoints: 2.8, gain: 1.35, grain: 0.12, fade: 0.72...0.88)

    public static func strokes() -> [HeatStroke] {
        var strokes = [
            HeatStroke(
                path: EchoGeometry.line(y: appIconCenter.y, from: 0, to: size.width),
                width: horizonWidth, heat: horizonHeat, cap: .butt)
        ]
        for index in 0..<echoes.count {
            strokes.append(
                HeatStroke(
                    path: EchoGeometry.ring(center: appIconCenter, radius: echoes.radius(index), mouth: true),
                    width: echoes.width(index), heat: echoes.heat(index)))
        }
        return strokes
    }
}

/// The welcome's art: the mark on a horizon, and its echoes rising out of it once.
///
/// The mark comes into focus, the horizon draws out from it, then the echoes leave one after
/// another. Each echo is launched fast and slows as it spreads, the way a ripple does, so it starts
/// smeared, wide and dim, and sharpens as it settles: motion blur along its own path. It also
/// leaves hot and cools to its resting heat. The design is "21 Welcome" in Paper.
public enum WelcomeArt {
    public static let size = CGSize(width: 600, height: 300)
    public static let development = HeatDevelopment(blurPoints: 2.6, gain: 1.3, grain: 0.12)

    private static let horizonY: CGFloat = 244
    private static let markUnit: CGFloat = 0.42
    private static let horizonWidth: CGFloat = 3.6
    private static let horizonHeat: CGFloat = 0.6
    private static let echoes = EchoFalloff(
        firstRadius: 64, step: 22.8, count: 16, width: 4.2, coldestHeat: 0.2)

    private static let markFocusSeconds = 0.45
    private static let horizonStartSeconds = 0.18
    private static let horizonSeconds = 0.7
    private static let firstEchoSeconds = 0.3
    private static let echoIntervalSeconds = 0.045
    private static let echoTravelSeconds = 0.95
    /// How fast a launched echo slows down: higher settles sooner.
    private static let echoDecay: CGFloat = 4.5
    /// How much wider than at rest an echo is at full speed.
    private static let motionBlurStretch: CGFloat = 2.4
    /// How much wider the mark is while it comes into focus.
    private static let focusStretch: CGFloat = 1.2
    /// An echo fades in over this share of its travel, so it never pops.
    private static let launchFadeShare: CGFloat = 0.08

    /// When the last echo settles.
    public static var duration: Double {
        firstEchoSeconds + Double(echoes.count - 1) * echoIntervalSeconds + echoTravelSeconds
    }

    private static var center: CGPoint { CGPoint(x: size.width / 2, y: horizonY) }

    /// The art `seconds` after it starts. At `duration` and later it rests.
    public static func strokes(at seconds: Double) -> [HeatStroke] {
        let focus = easeOut(seconds / markFocusSeconds)
        let stretch = 1 + focusStretch * (1 - focus)
        let markHeat = focus / stretch
        var strokes = [horizon(at: seconds)].compactMap { $0 }
        for index in 0..<echoes.count {
            if let echo = echo(index, at: seconds) { strokes.append(echo) }
        }
        strokes += EchoGeometry.mark(
            center: center, unit: markUnit, heats: Array(repeating: markHeat, count: 4),
            widthScale: stretch)
        return strokes
    }

    private static func horizon(at seconds: Double) -> HeatStroke? {
        let drawn = easeOut((seconds - horizonStartSeconds) / horizonSeconds)
        guard drawn > 0 else { return nil }
        let half = size.width / 2 * drawn
        return HeatStroke(
            path: EchoGeometry.line(y: horizonY, from: center.x - half, to: center.x + half),
            width: horizonWidth, heat: horizonHeat, cap: .butt)
    }

    private static func echo(_ index: Int, at seconds: Double) -> HeatStroke? {
        let launch = firstEchoSeconds + Double(index) * echoIntervalSeconds
        let travel = CGFloat(min(max((seconds - launch) / echoTravelSeconds, 0), 1))
        guard travel > 0 else { return nil }
        let spread = (1 - exp(-echoDecay * travel)) / (1 - exp(-echoDecay))
        let speed = travel >= 1 ? 0 : exp(-echoDecay * travel)
        let startRadius = (EchoGeometry.markRadiusUnits.last ?? 0) * markUnit
        let radius = startRadius + (echoes.radius(index) - startRadius) * spread
        let stretch = 1 + motionBlurStretch * speed
        let restHeat = echoes.heat(index)
        let cooling = restHeat + (1 - restHeat) * (1 - spread)
        let fadeIn = min(travel / launchFadeShare, 1)
        return HeatStroke(
            path: EchoGeometry.ring(center: center, radius: radius, mouth: false),
            width: echoes.width(index) * stretch, heat: cooling * fadeIn / stretch)
    }

    private static func easeOut(_ value: Double) -> CGFloat {
        let clamped = CGFloat(min(max(value, 0), 1))
        return 1 - pow(1 - clamped, 3)
    }
}

/// The small e in onboarding's footer: one part heats up for each finished step, bar first, then
/// each ring outward. Parts still to come stay cold, a dark red that only hints at the shape.
public enum ProgressMarkArt {
    public static let partCount = 4
    private static let coldHeat: CGFloat = 0.24
    /// The mark spans this share of its square, so the heat dies out before the square's edge and
    /// the picture never shows as a tile.
    private static let markShare: CGFloat = 0.74
    /// The mark's width in logo units: the outer ring's diameter plus one stroke.
    private static let markWidthUnits: CGFloat = 2 * 84 + EchoGeometry.markStrokeUnits

    /// Little diffusion at this size, so the rings stay apart and read as the logo.
    public static let development = HeatDevelopment(blurPoints: 0.45, gain: 1.2, grain: 0)

    public static func strokes(heated: Int, side: CGFloat) -> [HeatStroke] {
        let heats = (0..<partCount).map { $0 < heated ? 1 : coldHeat }
        return EchoGeometry.mark(
            center: CGPoint(x: side / 2, y: side / 2), unit: side * markShare / markWidthUnits, heats: heats)
    }
}
