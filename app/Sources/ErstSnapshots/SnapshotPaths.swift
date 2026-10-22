import Foundation

/// Where ErstSnapshots writes renders and where it finds brand assets.
enum SnapshotPaths {
    static var root: URL {
        if let override = ProcessInfo.processInfo.environment["ERST_ROOT"] {
            return URL(fileURLWithPath: override)
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return current.lastPathComponent == "app" ? current.deletingLastPathComponent() : current
    }

    static var mark: URL {
        root.appending(path: "brand/logo/mark.svg")
    }

    static func createSnapshotsFolder() throws -> URL {
        let folder = root.appending(path: ".erst-dev/snapshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
