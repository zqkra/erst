import CoreGraphics
import Foundation

/// The echo's geometry: the mark's rings, and the rings that keep spreading out of it.
///
/// Positions are in points with the origin at the top left, so the brand art reads like its
/// Paper designs. One logo unit is one 200th of the logo's drawing, where rings sit 28 apart.
enum EchoGeometry {
    /// The mark's ring radii in logo units.
    static let markRadiusUnits: [CGFloat] = [28, 56, 84]
    /// The heat stroke of a mark ring. Wider than the logo's 13, as the icon draws it, so the rings
    /// diffuse into coral where they meet.
    static let markStrokeUnits: CGFloat = 16
    /// The lower arcs end this far below the right horizontal, which opens the mouth of the e.
    static let mouthRadians: CGFloat = 38 * .pi / 180
    /// Enough points per radian that a 400 point ring stays round at 2x.
    private static let segmentsPerRadian: CGFloat = 40

    /// A ring of the e: the closed upper half, and with `mouth` the lower arc that stops at the
    /// mouth. Without it, only the upper half, a ring rising from a horizon.
    static func ring(center: CGPoint, radius: CGFloat, mouth: Bool) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: arc(center: center, radius: radius, from: .pi, to: 2 * .pi))
        if mouth {
            path.addLines(between: arc(center: center, radius: radius, from: .pi, to: mouthRadians))
        }
        return path
    }

    /// A horizontal line through `y`.
    static func line(y: CGFloat, from start: CGFloat, to end: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: start, y: y), CGPoint(x: end, y: y)])
        return path
    }

    /// The mark's three rings and its bar, `unit` points per logo unit. `heats` gives each part's
    /// heat in the order bar, inner ring, middle ring, outer ring.
    static func mark(center: CGPoint, unit: CGFloat, heats: [CGFloat], widthScale: CGFloat = 1)
        -> [HeatStroke]
    {
        let outer = (markRadiusUnits.last ?? 0) * unit
        let bar = line(y: center.y, from: center.x - outer, to: center.x + outer)
        let rings = markRadiusUnits.map { ring(center: center, radius: $0 * unit, mouth: true) }
        let parts = [bar] + rings
        let width = markStrokeUnits * unit * widthScale
        return zip(parts, heats).map { path, heat in HeatStroke(path: path, width: width, heat: heat) }
    }

    /// Points along a circle at y-down angles: pi is the left end, 1.5 pi the top, 0.5 pi the
    /// bottom.
    private static func arc(center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat)
        -> [CGPoint]
    {
        let count = max(8, Int((abs(end - start) * segmentsPerRadian).rounded(.up)))
        return (0...count).map { index in
            let angle = start + (end - start) * CGFloat(index) / CGFloat(count)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }
}

/// Echoes cool as they spread: a near ring is wide and hot, a far one thin and cold.
struct EchoFalloff {
    let firstRadius: CGFloat
    let step: CGFloat
    let count: Int
    let width: CGFloat
    let coldestHeat: CGFloat

    private static let widthGrowth: CGFloat = 1.6
    private static let widthShrink: CGFloat = 0.9
    private static let coolingExponent: CGFloat = 0.8

    func radius(_ index: Int) -> CGFloat { firstRadius + step * CGFloat(index) }

    func distance(_ index: Int) -> CGFloat { CGFloat(index) / CGFloat(max(count - 1, 1)) }

    func width(_ index: Int) -> CGFloat {
        width * (Self.widthGrowth - Self.widthShrink * distance(index))
    }

    func heat(_ index: Int) -> CGFloat {
        1 - (1 - coldestHeat) * pow(distance(index), Self.coolingExponent)
    }
}
