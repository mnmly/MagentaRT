import Foundation

/// Model-shape constants mirrored from `magentart::core` (mlx_engine.h). The
/// engine is fixed at 25 Hz: one output frame is `frameSamples` = 1920 samples
/// of stereo audio at 48 kHz = 40 ms.
public enum MagentaRTConstants {
    /// Samples per channel per generated frame (1920 @ 48 kHz → 40 ms).
    public static let frameSamples = 1920
    /// Output sample rate.
    public static let sampleRate = 48_000
    /// Frame rate (Hz). Generating faster than this is "real-time".
    public static let frameRate = 25
    public static let channels = 2
}
