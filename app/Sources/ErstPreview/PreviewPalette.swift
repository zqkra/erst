import CoreGraphics

/// Flat colors for the synthetic capture frames. They never appear in the app chrome.
enum PreviewPalette {
    static func rgb(_ hex: UInt32) -> CGColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static let window = rgb(0x101113)
    static let chrome = rgb(0x181A1D)
    static let hairlineDark = rgb(0x2A2B2E)
    static let lightWindow = rgb(0xFBF8F2)
    static let lightPanel = rgb(0xF4F1EB)
    static let lightSelection = rgb(0xF3E8C9)
    static let hairlineLight = rgb(0xDDD6CA)
    static let darkInk = rgb(0xEDE9E2)
    static let darkSecondary = rgb(0x9B978F)
    static let lightInk = rgb(0x22211F)
    static let lightSecondary = rgb(0x77736C)
    static let butter = rgb(0xF8D677)
    static let butterInk = rgb(0x1A1A1A)
    static let coral = rgb(0xEF7A68)
    static let orange = rgb(0xF6A563)
    static let green = rgb(0xD9FDD3)
    static let terminal = rgb(0x15171A)
    static let editorSidebar = rgb(0x16181B)
    static let editorBar = rgb(0x202329)
    static let editorPage = rgb(0x1B1D21)
    static let whatsAppPage = rgb(0xEFE9E1)
    static let youtubePage = rgb(0xF9F8F6)
    /// The color tokens on the design system card in the X feed.
    static let swatches = [coral, orange, butter, rgb(0x5B6B78), lightWindow]
    static let thumbnails = [
        rgb(0x49667A), rgb(0xA65B4A), rgb(0x5C7357),
        rgb(0x8C7446), rgb(0x4C5568), rgb(0x7A5A66),
    ]
}
