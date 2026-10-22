import Foundation
import SwiftUI

/// Timeline geometry in points, from the Timeline section of the design.
public enum TimelineMetrics {
    public static let defaultPointsPerFrame: CGFloat = 6
    static let pointsPerFrameRange: ClosedRange<CGFloat> = 2...24
    static let zoomStep: CGFloat = 1.25
    static let prefetchFrames = 200
    static let imageCacheRadius = 3
    static let imageMaxPixels = 2000
    static let selectionImageDelay = Duration.milliseconds(60)
    static let prefetchImageDelay = Duration.milliseconds(40)

    // Scrims over the captured frame, for legibility only.
    static let topScrimHeight: CGFloat = 120
    static let bottomScrimHeight: CGFloat = 340
    static let topScrimOpacity: Double = 0.7
    static let bottomScrimMiddleOpacity: Double = 0.55
    static let bottomScrimOpacity: Double = 0.8
    static let bottomScrimMiddleLocation: CGFloat = 0.6

    // Search capsule.
    static let searchTopInset: CGFloat = 16
    static let searchWidth: CGFloat = 560
    static let searchWidthFraction: CGFloat = 0.45
    static let searchHeight: CGFloat = 46
    static let searchCornerRadius: CGFloat = 23
    static let searchHorizontalPadding: CGFloat = 18
    static let searchGap: CGFloat = 12
    static let searchMarkSize: CGFloat = 20
    static let searchShadowRadius: CGFloat = 24
    static let searchShadowY: CGFloat = 8
    static let searchShadowOpacity: Double = 0.22
    /// Search opened from the capsule, when the host gives no size: the share of the timeline
    /// that 65% of the visible frame takes inside the timeline's 80% by 90%.
    static let searchPanelWidthFraction: CGFloat = 0.8125
    static let searchPanelHeightFraction: CGFloat = 0.72
    /// The open panel's top band around the query row: padding 24, the row, padding 24.
    static let searchBandHeight: CGFloat = 74
    /// How far the dock sinks while search is open over it.
    static let searchDockSlide: CGFloat = 28

    // Dock.
    static let dockInset: CGFloat = 20
    static let dockHeight: CGFloat = 194
    static let dockCornerRadius: CGFloat = 30
    static let dockPaddingTop: CGFloat = 18
    static let dockPaddingBottom: CGFloat = 16
    static let dockPaddingHorizontal: CGFloat = 24
    static let dockRowGap: CGFloat = 14
    static let dockShadowRadius: CGFloat = 40
    static let dockShadowY: CGFloat = 16
    static let dockShadowOpacity: Double = 0.3

    // First row: source, time, actions.
    static let headerHeight: CGFloat = 38
    static let sourceIconSize: CGFloat = 30
    static let sourceIconCornerRadius: CGFloat = 8
    static let sourceIconGap: CGFloat = 12
    static let sourceGap: CGFloat = 12
    static let sourceTextGap: CGFloat = 2
    static let timeGap: CGFloat = 10
    static let actionsCapsuleHeight: CGFloat = 38
    static let actionsCapsulePadding: CGFloat = 6
    static let actionsGap: CGFloat = 2
    static let actionButtonWidth: CGFloat = 40
    static let actionButtonHeight: CGFloat = 30
    static let actionGlyphSize: CGFloat = 17

    // App icons.
    /// The corner radius of a letter tile as a fraction of its side: 8 at 30, 3.8 at 14.
    static let monogramCornerFraction: CGFloat = 0.27

    // Second row: track and zoom.
    static let trackHeight: CGFloat = 104
    static let trackZoomGap: CGFloat = 16
    static let zoomColumnWidth: CGFloat = 176
    static let zoomGap: CGFloat = 10

    // Segment chips.
    static let chipHeight: CGFloat = 22
    static let chipCornerRadius: CGFloat = 11
    static let chipSelectedCornerRadius: CGFloat = 6
    static let chipGap: CGFloat = 4
    static let chipLeadingPadding: CGFloat = 4
    static let chipTrailingPadding: CGFloat = 8
    static let chipContentGap: CGFloat = 6
    static let chipMinimumIconWidth: CGFloat = 22
    static let chipMinimumDetailWidth: CGFloat = 16
    static let chipIconSize: CGFloat = 14
    /// A chip too narrow for its name centers its icon this far from each side, and shrinks it no
    /// smaller than the second value, below which an app icon stops reading.
    static let chipIconOnlyInset: CGFloat = 2
    static let chipMinimumIconSide: CGFloat = 8
    static let chipIconCornerRadius: CGFloat = 4
    static let chipNameFontSize: CGFloat = 11
    static let chipDetailFontSize: CGFloat = 11
    static let sessionChipWidth: CGFloat = 70
    static let sessionChipLabelPadding: CGFloat = 8
    static let sessionGap: CGFloat = sessionChipWidth + chipGap * 2
    static let stripeWidth: CGFloat = 4
    static let stripePeriod: CGFloat = 8

    // Heat bars: six activity levels, from the approved heat strip.
    static let heatTop: CGFloat = 32
    static let heatHeight: CGFloat = 44
    static let heatBaseHeight: CGFloat = 10
    static let heatLevelStep: CGFloat = 6.5
    static let heatBarGap: CGFloat = 1
    static let heatMinimumWidth: CGFloat = 1
    static let heatCornerRadius: CGFloat = 1.5

    // Hour labels.
    static let hourLabelTop: CGFloat = 86
    static let hourLabelMinimumSpacing: CGFloat = 48

    // Playhead.
    static let playheadLineTop: CGFloat = 26
    static let playheadLineHeight: CGFloat = 56
    static let playheadLineWidth: CGFloat = 2
    static let playheadKnobTop: CGFloat = 22
    static let playheadKnobSize: CGFloat = 12
    static let playheadRingWidth: CGFloat = 3
    static let playheadCornerRadius: CGFloat = 1

    // Month grid: one column per day, one row per wall-clock hour.
    static let monthTitleHeight: CGFloat = 14
    static let monthGridTop: CGFloat = 24
    static let monthGridBottom: CGFloat = 80
    static let monthCellGapFraction: CGFloat = 0.22
    static let monthCellMinimumGap: CGFloat = 2
    static let monthColumnCornerRadius: CGFloat = 3
    static let monthColumnHighlightInset: CGFloat = 4
    static let monthColumnHighlightCornerRadius: CGFloat = 6
    static let monthCursorRingWidth: CGFloat = 1.5
    static let monthCursorOutlineWidth: CGFloat = 4
    static let monthCursorRingOutset: CGFloat = 2
    static let monthHoverRingWidth: CGFloat = 1
    /// Below this column width only every other day carries its number.
    static let monthDayLabelMinimumSpacing: CGFloat = 18
    /// Scrolling this far sideways moves one day, and this far up or down moves one hour.
    static let monthScrollPointsPerDay: CGFloat = 24
    static let monthScrollPointsPerHour: CGFloat = 10
    /// A future hour draws the quiet color at this strength.
    static let monthFutureOpacity: CGFloat = 0.4

    // Zoom column.
    static let scaleHeight: CGFloat = 34
    static let scaleCornerRadius: CGFloat = 17
    static let scalePadding: CGFloat = 3
    static let scalePillCornerRadius: CGFloat = 14
    static let scalePillShadowRadius: CGFloat = 2
    static let scalePillShadowY: CGFloat = 1
    static let scalePillShadowOpacity: Double = 0.2
    static let nowOpacityWhenDisabled: Double = 0.5

    /// The x of the track's center inside a dock row of this width.
    static func trackCenterX(rowWidth: CGFloat) -> CGFloat {
        max(0, (rowWidth - zoomColumnWidth - trackZoomGap) / 2)
    }

    /// The track's width inside a surface of this width, after the dock's insets and padding.
    public static func trackWidth(surfaceWidth: CGFloat) -> CGFloat {
        let inner =
            surfaceWidth - dockInset * 2 - dockPaddingHorizontal * 2 - zoomColumnWidth
            - trackZoomGap
        return max(0, inner)
    }
}

/// The zoom presets above the Now button: three spans of frames, and the month of days.
public enum TimelineScale: String, CaseIterable, Identifiable, Sendable {
    case hour
    case sixHours
    case day
    case month

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: "1h"
        case .sixHours: "6h"
        case .day: "Day"
        case .month: "Month"
        }
    }

    /// The span of frames a frame scale fits into the track. Month shows days, not frames.
    var frameSpan: TimeInterval? {
        switch self {
        case .hour: 3_600
        case .sixHours: 21_600
        case .day: 86_400
        case .month: nil
        }
    }
}
