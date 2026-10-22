import Foundation

/// Errors raised while reducing a frame to a luma thumbnail.
public enum ThumbnailerError: Error, LocalizedError, Equatable {
    /// The pixel buffer is not BGRA.
    case unsupportedPixelFormat(UInt32)
    /// The pixel buffer has no CPU accessible base address.
    case missingBaseAddress
    /// vImage could not scale the frame.
    case scaleFailed(Int)
    /// vImage could not convert the frame to luma.
    case luminanceFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPixelFormat(let format):
            "Unsupported pixel format \(format)."
        case .missingBaseAddress:
            "The pixel buffer has no base address."
        case .scaleFailed(let code):
            "vImage scaling failed with \(code)."
        case .luminanceFailed(let code):
            "vImage luma conversion failed with \(code)."
        }
    }
}
