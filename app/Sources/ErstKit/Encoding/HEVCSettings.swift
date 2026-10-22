import AVFoundation
import VideoToolbox

/// AVAssetWriter video settings shared by the live writer and the reducer.
enum HEVCSettings {
    static func outputSettings(width: Int, height: Int, compression: Compression) -> [String: Any] {
        let compressionProperties: [String: Any] = [
            AVVideoQualityKey: compression.qualityValue,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalDurationKey: 300,
            AVVideoExpectedSourceFrameRateKey: 1,
        ]
        let encoderSpecification: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
        ]
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties,
            AVVideoEncoderSpecificationKey: encoderSpecification,
        ]
    }
}
