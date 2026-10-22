import CoreGraphics

/// Onboarding's window and the shared geometry of its steps. The design is the page
/// "03 Install & Setup" in Paper.
public enum OnboardingLayout {
    public static let windowWidth: CGFloat = 600
    public static let windowHeight: CGFloat = 560
    /// Copy and rows start this far from the window's sides.
    static let sideInset: CGFloat = 48
    /// A step's title starts this far down, under the transparent title bar.
    static let titleTop: CGFloat = 84
    static let bottomInset: CGFloat = 40
    static let detailWidth: CGFloat = 440
    /// The welcome's copy starts under the art's horizon.
    static let welcomeCopyTop: CGFloat = 318
    static let welcomeDetailWidth: CGFloat = 400
    static let rowHeight: CGFloat = 64
    static let rowIconSide: CGFloat = 38
    static let rowIconRadius: CGFloat = 10
    static let rowTrailingWidth: CGFloat = 110
    static let progressMarkSide: CGFloat = 30
    static let keyHeight: CGFloat = 72
    static let keyModifierWidth: CGFloat = 84
    static let spaceKeyWidth: CGFloat = 236
    static let keyRadius: CGFloat = 14
    /// The key's lower edge, the depth of a physical key.
    static let keyDepth: CGFloat = 3
    static let smallKeyHeight: CGFloat = 28
    static let smallKeyRadius: CGFloat = 7
    static let smallKeyDepth: CGFloat = 2
}
