import ErstModel
import Foundation

/// The `erst` link in `/usr/local/bin`, which `/etc/paths` puts on every shell's PATH.
///
/// Writing there needs an administrator, so the link is made through `osascript` with
/// administrator privileges: the standard macOS password prompt, in its own process, so the app
/// stays responsive while it is up.
struct CommandLineLink: Sendable {
    static let path = "/usr/local/bin/erst"
    /// The tool inside this copy of Erst.
    let target: String

    /// AppleScript's error number when the person cancels the password prompt.
    private static let userCanceledCode = "-128"
    private static let prompt = "Erst wants to add the erst command to your terminal."

    func state() -> CommandLineToolState {
        let manager = FileManager.default
        guard let destination = try? manager.destinationOfSymbolicLink(atPath: Self.path) else {
            return manager.fileExists(atPath: Self.path) ? .otherCopy : .notInstalled
        }
        return destination == target ? .installed : .otherCopy
    }

    func install() async throws {
        try await runAsAdministrator(
            "/bin/mkdir -p /usr/local/bin && /bin/ln -sfn \(quoted(target)) \(quoted(Self.path))")
    }

    func uninstall() async throws {
        try await runAsAdministrator("/bin/rm -f \(quoted(Self.path))")
    }

    private func runAsAdministrator(_ command: String) async throws {
        let script =
            "do shell script \"\(escaped(command))\" with administrator privileges "
            + "with prompt \"\(Self.prompt)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                let message = String(
                    decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if finished.terminationStatus == 0 || message.contains(Self.userCanceledCode) {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: AgentClientError.commandLineFailed(
                            reason: message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// A shell word in single quotes, safe for any path.
    private func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The text inside an AppleScript string literal.
    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
