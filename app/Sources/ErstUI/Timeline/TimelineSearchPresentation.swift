import CoreGraphics
import Observation
import SwiftUI

/// Search opened from the timeline: the capsule grows into the search panel over the dimmed
/// frame, and closing shrinks the panel back into the capsule.
///
/// `isPresented` keeps the search in the tree for the whole open and close. `progress` is the
/// value the morph springs toward: 0 is the capsule, 1 is the open panel. A close that an open
/// interrupts never removes the search.
@MainActor
@Observable
// ObservableObject lets the overlay host keep one presentation per timeline route.
public final class TimelineSearchPresentation: ObservableObject {
    public private(set) var isPresented: Bool
    private(set) var progress: CGFloat
    /// The open panel's size, the same as search opened on its own. Its top edge stays on the
    /// capsule's top edge. Nil fits it to the timeline.
    public let panelSize: CGSize?
    /// Set by the morph from the environment, so a close from the host also reduces motion.
    var reducesMotion = false
    /// A snapshot's presentation stays at the progress it was made with.
    private let holdsProgress: Bool

    /// Critically damped: a click or a shortcut carries no momentum to overshoot with. The way
    /// back is quicker than the way in, because closing is the system answering, not the user
    /// deciding.
    static let openAnimation = Animation.spring(duration: 0.38, bounce: 0)
    static let closeAnimation = Animation.spring(duration: 0.24, bounce: 0)
    static let reducedAnimation = Animation.easeInOut(duration: 0.18)

    /// A `progress` above 0 starts presented and stays there, for a snapshot of the morph.
    public init(panelSize: CGSize? = nil, progress: CGFloat = 0) {
        self.panelSize = panelSize
        self.progress = progress
        isPresented = progress > 0
        holdsProgress = progress > 0
    }

    public var isOpen: Bool { isPresented && progress > 0 }

    public func toggle() {
        if isPresented && progress > 0 {
            close()
        } else {
            open()
        }
    }

    /// Puts the search in the tree at the capsule's shape. The morph expands it once it appears;
    /// a close still in flight turns around instead.
    public func open() {
        if isPresented {
            expand()
        } else {
            isPresented = true
        }
    }

    func expand() {
        guard !holdsProgress, progress < 1 else { return }
        withAnimation(reducesMotion ? Self.reducedAnimation : Self.openAnimation) {
            progress = 1
        }
    }

    public func close() {
        guard isPresented else { return }
        withAnimation(
            reducesMotion ? Self.reducedAnimation : Self.closeAnimation,
            completionCriteria: .logicallyComplete
        ) {
            progress = 0
        } completion: { [weak self] in
            guard let self, self.progress == 0 else { return }
            self.isPresented = false
        }
    }
}
