import AppKit
import CoreGraphics
import ObjectiveC

/// A virtual display at two pixels per point that lives as long as this process. The live captures
/// draw on it, so they keep Retina detail on a Mac whose own screen draws one pixel per point. It
/// uses CoreGraphics' private virtual display classes, the ones screen sharing tools use.
@MainActor
enum RetinaDisplay {
    /// Twice the largest stage: macOS gives a display this size its 2x mode by default.
    private static let points = (width: 3120, height: 2200)
    private static var display: NSObject?

    /// Makes the display and waits until CoreGraphics shows it at 2x. AppKit reads its screens once
    /// and refreshes them only from window server events, which this tool never reads, so this runs
    /// before anything asks AppKit for a screen.
    static func prepare() async {
        display = make()
        guard let id else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let mode = CGDisplayCopyDisplayMode(id), mode.pixelWidth == 2 * mode.width { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The display's screen once it draws at 2x, else nil.
    static var screen: NSScreen? {
        guard let id else { return nil }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.backingScaleFactor == 2 ? screen : nil
    }

    private static var id: CGDirectDisplayID? {
        (display?.value(forKey: "displayID") as? NSNumber)?.uint32Value
    }

    private static func make() -> NSObject? {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
            let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
            let displayClass = NSClassFromString("CGVirtualDisplay"),
            let modeClass = NSClassFromString("CGVirtualDisplayMode")
        else { return nil }
        let descriptor = descriptorClass.init()
        descriptor.setValue(DispatchQueue.main, forKey: "queue")
        descriptor.setValue("Erst Snapshots", forKey: "name")
        descriptor.setValue(points.width * 2, forKey: "maxPixelsWide")
        descriptor.setValue(points.height * 2, forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: NSSize(width: 600, height: 423)), forKey: "sizeInMillimeters")
        descriptor.setValue(0x3A10, forKey: "vendorID")
        descriptor.setValue(0x0E57, forKey: "productID")
        descriptor.setValue(1, forKey: "serialNum")
        guard
            let allocated = (displayClass as AnyObject).perform(NSSelectorFromString("alloc"))?
                .takeUnretainedValue(),
            let display = allocated.perform(NSSelectorFromString("initWithDescriptor:"), with: descriptor)?
                .takeRetainedValue() as? NSObject,
            let modeAllocated = (modeClass as AnyObject).perform(NSSelectorFromString("alloc"))?
                .takeUnretainedValue()
        else { return nil }

        typealias ModeInit =
            @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>
        let modeSelector = NSSelectorFromString("initWithWidth:height:refreshRate:")
        guard let modeIMP = class_getMethodImplementation(modeClass, modeSelector) else { return nil }
        let mode = unsafeBitCast(modeIMP, to: ModeInit.self)(
            modeAllocated, modeSelector, UInt32(points.width), UInt32(points.height), 60
        ).takeRetainedValue()

        let settings = settingsClass.init()
        settings.setValue(1, forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")
        typealias Apply = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let applySelector = NSSelectorFromString("applySettings:")
        guard let applyIMP = class_getMethodImplementation(displayClass, applySelector),
            unsafeBitCast(applyIMP, to: Apply.self)(display, applySelector, settings)
        else { return nil }
        return display
    }
}
