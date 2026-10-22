import AppKit

/// What the dock's action buttons do with the selected frame.
extension TimelineModel {
    public func copyImage() {
        guard let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        ])
    }

    public func openSource() {
        guard let moment = selectedMoment else { return }
        if let url = moment.url {
            NSWorkspace.shared.open(url)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: moment.app.bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
