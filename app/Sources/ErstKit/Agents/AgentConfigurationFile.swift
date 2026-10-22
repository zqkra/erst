import Foundation

/// One agent configuration file, read through any symlink so the link and its target survive writes.
struct AgentConfigurationFile {
    let url: URL
    let original: Data?

    var backupURL: URL {
        url.appendingPathExtension("erst-backup")
    }

    init(url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        self.url = resolved
        do {
            original = try Data(contentsOf: resolved)
        } catch {
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain,
                failure.code == CocoaError.fileReadNoSuchFile.rawValue
            else {
                throw AgentClientError.readFailed(file: resolved, reason: error.localizedDescription)
            }
            original = nil
        }
    }

    func write(_ content: Data) throws {
        guard content != original else { return }
        let files = FileManager.default
        let current = try reread()
        guard current == original else {
            throw AgentClientError.writeFailed(file: url, reason: Self.changedReason)
        }
        let permissions: Any?
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            permissions =
                original == nil ? nil : try files.attributesOfItem(atPath: url.path)[.posixPermissions]
        } catch {
            throw AgentClientError.writeFailed(file: url, reason: error.localizedDescription)
        }
        if let original {
            do {
                // Refresh on every write so a restore never drops changes made after Erst's first edit.
                try original.write(to: backupURL, options: .atomic)
                if let permissions {
                    try files.setAttributes([.posixPermissions: permissions], ofItemAtPath: backupURL.path)
                }
            } catch {
                throw AgentClientError.backupFailed(file: url, reason: error.localizedDescription)
            }
        }
        do {
            try content.write(to: url, options: .atomic)
            if let permissions {
                try files.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
        } catch {
            throw AgentClientError.writeFailed(file: url, reason: error.localizedDescription)
        }
    }

    private static let changedReason = "The file changed while Erst was editing it. Try again."

    private func reread() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain,
                failure.code == CocoaError.fileReadNoSuchFile.rawValue
            else {
                throw AgentClientError.writeFailed(file: url, reason: Self.changedReason)
            }
            return nil
        }
    }
}
