import Foundation

/// Minimal 32-bit float WAV writer, mirroring `write_wav` in
/// `examples/hello_mrt2/main.cpp` (IEEE-float, interleaved).
public enum WAVWriter {
    /// Write interleaved float32 samples to a `.wav` file.
    public static func write(
        interleaved: [Float],
        to url: URL,
        sampleRate: Int = MagentaRTConstants.sampleRate,
        channels: Int = MagentaRTConstants.channels
    ) throws {
        let bitsPerSample: UInt16 = 32
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(interleaved.count) * UInt32(bitsPerSample / 8)
        let chunkSize = 36 + dataSize

        var data = Data()
        func put(_ s: String) { data.append(contentsOf: s.utf8) }
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        put("RIFF"); put(chunkSize); put("WAVE")
        put("fmt "); put(UInt32(16))
        put(UInt16(3))                  // audio format: 3 = IEEE float
        put(UInt16(channels))
        put(UInt32(sampleRate))
        put(byteRate)
        put(blockAlign)
        put(bitsPerSample)
        put("data"); put(dataSize)
        interleaved.withUnsafeBytes { data.append(contentsOf: $0) }

        try data.write(to: url)
    }

    /// Interleave two equal-length channel buffers, then write.
    public static func write(
        _ stereo: OfflineEngine.StereoBuffer,
        to url: URL,
        sampleRate: Int = MagentaRTConstants.sampleRate
    ) throws {
        precondition(stereo.left.count == stereo.right.count)
        var interleaved = [Float](repeating: 0, count: stereo.left.count * 2)
        for i in 0..<stereo.left.count {
            interleaved[2 * i] = stereo.left[i]
            interleaved[2 * i + 1] = stereo.right[i]
        }
        try write(interleaved: interleaved, to: url, sampleRate: sampleRate, channels: 2)
    }
}
