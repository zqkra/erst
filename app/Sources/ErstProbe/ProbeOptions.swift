import Foundation

/// Command line options for the probe.
struct ProbeOptions {
    var isVerification = false
    var isControlExercise = false
    var isProduction = false
    var disablesIdleGate = false
    var seconds = 20
    var dataDirectory: URL?
    var traceURL: URL?

    static let usage = """
        Usage: ErstProbe [seconds] [--production] [--no-idle-gate] [--data-dir <path>] [--trace <file>]
               ErstProbe --verify
               ErstProbe [seconds] [--exercise-controls]
        """
}

/// A rejected command line.
struct ProbeOptionError: Error, CustomStringConvertible {
    let description: String
}

extension ProbeOptions {
    static func parse(_ arguments: [String]) throws -> ProbeOptions {
        var options = ProbeOptions()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            switch arguments[index] {
            case "--verify":
                options.isVerification = true
            case "--exercise-controls":
                options.isControlExercise = true
            case "--production":
                options.isProduction = true
            case "--no-idle-gate":
                options.disablesIdleGate = true
            case "--data-dir":
                index = arguments.index(after: index)
                guard index < arguments.endIndex else {
                    throw ProbeOptionError(description: "--data-dir needs a path")
                }
                let path = (arguments[index] as NSString).expandingTildeInPath
                options.dataDirectory = URL(fileURLWithPath: path, isDirectory: true)
            case "--trace":
                index = arguments.index(after: index)
                guard index < arguments.endIndex else {
                    throw ProbeOptionError(description: "--trace needs a file path")
                }
                let path = (arguments[index] as NSString).expandingTildeInPath
                options.traceURL = URL(fileURLWithPath: path)
            default:
                if let value = Int(arguments[index]) {
                    options.seconds = min(max(value, 1), 3600)
                }
            }
            index = arguments.index(after: index)
        }
        return options
    }
}
