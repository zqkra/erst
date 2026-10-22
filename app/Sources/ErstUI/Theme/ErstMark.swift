import CoreGraphics
import SwiftUI

/// The Erst mark: three concentric rings with a lower-right aperture and a bar.
public struct ErstMark: Shape {
    private let strokeFraction: CGFloat = 0.065
    private let radiusFractions: [CGFloat] = [0.42, 0.28, 0.14]
    private let barWidthFraction: CGFloat = 0.905
    // The SVG's lower arcs end at (166.19, 151.72) on the radius-84 ring, 38 degrees below
    // the right horizontal.
    private let apertureDegrees: CGFloat = 38.0
    private let joinMiterLimit: CGFloat = 10

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let stroke = side * strokeFraction
        let rings = CGMutablePath()
        for fraction in radiusFractions {
            addRing(to: rings, center: center, radius: side * fraction)
        }
        let stroked = rings.copy(
            strokingWithWidth: stroke, lineCap: .butt, lineJoin: .miter, miterLimit: joinMiterLimit)
        let bar = CGPath(
            rect: CGRect(
                x: center.x - side * barWidthFraction / 2,
                y: center.y - stroke / 2,
                width: side * barWidthFraction,
                height: stroke
            ),
            transform: nil)
        return Path(stroked.union(bar, using: .winding))
    }

    private func addRing(to path: CGMutablePath, center: CGPoint, radius: CGFloat) {
        let left = CGPoint(x: center.x - radius, y: center.y)
        // addArc connects from the current point, so start each subpath at the shared left end.
        path.move(to: left)
        path.addArc(
            center: center, radius: radius, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        path.move(to: left)
        path.addArc(
            center: center, radius: radius, startAngle: .pi, endAngle: apertureRadians,
            clockwise: true)
    }

    private var apertureRadians: CGFloat {
        apertureDegrees * .pi / 180
    }
}
