import CoreText
import Foundation
import SwiftUI

/// Schibsted Grotesk from the bundled font files.
public enum Typography {
    private static let regularName = "SchibstedGrotesk-Regular"
    private static let mediumName = "SchibstedGrotesk-Regular_Medium"
    private static let semiboldName = "SchibstedGrotesk-Regular_SemiBold"
    private static let boldName = "SchibstedGrotesk-Regular_Bold"

    private static let registration: Void = registerFontFiles()

    /// Registers the bundled font files. Safe to call more than once.
    public static func registerFonts() {
        _ = registration
    }

    public static let display = make(56, .semibold, trackingEm: -0.04)
    public static let title = make(22, .semibold, trackingEm: -0.02)
    public static let headline = make(15, .semibold, trackingEm: -0.01)
    public static let body = make(13, .regular)
    public static let bodyMedium = make(13, .medium)
    public static let caption = make(12, .regular)
    public static let captionMedium = make(12, .medium)
    public static let query = make(20, .regular)
    public static let clock = make(24, .medium, trackingEm: -0.02)
    public static let stat = make(26, .semibold, trackingEm: -0.02)
    public static let panelTitle = make(20, .semibold, trackingEm: -0.02)
    public static let chipTitle = make(12, .medium)
    public static let chipSubtitle = make(11, .regular)
    public static let keycap = make(11, .medium)
    public static let eyebrow = make(11, .medium, trackingEm: 0.02)
    public static let tiny = make(10, .regular)
    /// Onboarding: the welcome's line, each step's title, the sentences under them, and the glyph
    /// on a keycap the user is asked to press.
    public static let welcomeTitle = make(32, .bold, trackingEm: -0.025)
    public static let stepTitle = make(30, .bold, trackingEm: -0.025)
    public static let lead = make(15, .regular)
    public static let keyGlyph = make(22, .regular)
    public static let icon = make(15, .medium)

    private static func make(
        _ size: CGFloat,
        _ weight: Font.Weight,
        trackingEm: CGFloat = 0
    ) -> ErstTextStyle {
        weighedFont(size: size, weight: weight, trackingEm: trackingEm)
    }

    private static func weighedFont(
        size: CGFloat,
        weight: Font.Weight,
        trackingEm: CGFloat
    ) -> ErstTextStyle {
        registerFonts()
        let font = Font.custom(postScriptName(for: weight), fixedSize: size)
        return ErstTextStyle(font: font, tracking: size * trackingEm)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: boldName
        case .semibold: semiboldName
        case .medium: mediumName
        default: regularName
        }
    }

    private static func registerFontFiles() {
        for directory in fontDirectories() {
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )) ?? []
            for file in files where file.pathExtension.lowercased() == "ttf" {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
        }
    }

    private static func fontDirectories() -> [URL] {
        // SwiftPM processes Resources into the bundle root, so look there as well as in Fonts.
        var candidates: [URL] = []
        if let bundledResources = Bundle.module.resourceURL {
            candidates.append(bundledResources)
            candidates.append(bundledResources.appendingPathComponent("Fonts"))
        }
        let executableFolder = Bundle.main.bundleURL.deletingLastPathComponent()
        let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let bundleNames = ["Erst_ErstUI.bundle"]
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Fonts"))
            candidates.append(resourceURL)
        }
        for name in bundleNames {
            for base in [resourceURL, executableFolder, Bundle.main.bundleURL] {
                let bundle = base.appendingPathComponent(name)
                candidates.append(bundle.appendingPathComponent("Contents/Resources/Fonts"))
                candidates.append(bundle.appendingPathComponent("Fonts"))
                candidates.append(bundle.appendingPathComponent("Contents/Resources"))
            }
        }
        candidates.append(executableFolder.appendingPathComponent("Fonts"))
        return candidates
    }
}
