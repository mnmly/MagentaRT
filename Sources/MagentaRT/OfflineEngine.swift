import Foundation
import MagentartCore

/// Swift wrapper over the C++ `magentart::bridge::OfflineEngine` facade
/// (`MLXEngine` underneath) for non-realtime, frame-by-frame generation.
///
/// Concurrency design: this `actor` is the sole owner of the non-Sendable C++
/// engine and serializes all access to it. It runs on a **dedicated serial
/// executor** (a `DispatchSerialQueue`) so the blocking C++ calls
/// (`loadModel`, `generateFrame`) occupy a private thread instead of starving a
/// shared cooperative-pool thread.
public actor OfflineEngine {
    public enum EngineError: Error, CustomStringConvertible {
        case initAssetsFailed(String)
        case loadFailed(String)
        case promptEncodeFailed
        case notLoaded
        case generateFailed(frame: Int)

        public var description: String {
            switch self {
            case .initAssetsFailed(let d): return "init_assets failed: \(d)"
            case .loadFailed(let p): return "load failed: \(p)"
            case .promptEncodeFailed: return "MusicCoCa text encode failed"
            case .notLoaded: return "no model loaded"
            case .generateFailed(let f): return "generate_frame failed at frame \(f)"
            }
        }
    }

    /// Stereo PCM result of a generation run: `frames * frameSamples` floats per
    /// channel, 48 kHz.
    public struct StereoBuffer: Sendable {
        public let left: [Float]
        public let right: [Float]
        public var sampleCount: Int { left.count }
    }

    // Dedicated serial executor — keeps blocking C++ calls off the global pool.
    private let queue = DispatchSerialQueue(label: "com.mnmly.magentart.offline")
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    // The C++ facade reference type. ARC-managed via SWIFT_SHARED_REFERENCE.
    private let engine = magentart.bridge.OfflineEngine.create()

    public init() {}

    // MARK: Lifecycle

    /// Load the TFLite MusicCoCa assets from `resourceDir/<subfolder>`.
    public func initAssets(resourceDir: String, subfolder: String = "musiccoca") throws {
        let ok = resourceDir.withCString { rd in
            subfolder.withCString { sf in engine.initAssets(rd, sf) }
        }
        guard ok else { throw EngineError.initAssetsFailed("\(resourceDir)/\(subfolder)") }
    }

    /// Load an exported `.mlxfn` transformer model.
    public func loadModel(_ mlxfnPath: String) throws {
        let ok = mlxfnPath.withCString { engine.loadModel($0) }
        guard ok else { throw EngineError.loadFailed(mlxfnPath) }
    }

    public var isLoaded: Bool { engine.isLoaded() }
    public var rvqDepth: Int { Int(engine.rvqDepth()) }
    public func unload() { engine.unload() }

    // MARK: Sampling parameters (atomic in C++)

    public func setSampling(
        temperature: Float? = nil,
        topK: Int? = nil,
        cfgMusiccoca: Float? = nil,
        cfgNotes: Float? = nil,
        cfgDrums: Float? = nil,
        seedRotation: Int? = nil
    ) {
        if let t = temperature { engine.setTemperature(t) }
        if let k = topK { engine.setTopK(Int32(k)) }
        if let v = cfgMusiccoca { engine.setCfgMusiccoca(v) }
        if let v = cfgNotes { engine.setCfgNotes(v) }
        if let v = cfgDrums { engine.setCfgDrums(v) }
        if let r = seedRotation { engine.setSeedRotation(Int32(r)) }
    }

    // MARK: Prompt

    /// Set a text prompt and await the async MusicCoCa encode (TFLite worker).
    public func setTextPrompt(_ text: String) async throws {
        text.withCString { engine.setTextPrompt($0) }
        while true {
            switch engine.textEncoderStatus() {   // 0 idle,1 fetching,2 ok,3 err
            case 2: return
            case 3: throw EngineError.promptEncodeFailed
            default: try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /// Drive generation with no text prompt (audio/prefill-only).
    public func maskPrompt() { engine.setMusiccocaMasked() }

    /// Set several weighted text prompts at once; awaits the MusicCoCa encode.
    public func setPrompts(_ prompts: [(text: String, weight: Float)]) async throws {
        engine.beginPrompts()
        for p in prompts { p.text.withCString { engine.addPrompt($0, p.weight) } }
        engine.commitPrompts()
        while true {
            switch engine.textEncoderStatus() {
            case 2: return
            case 3: throw EngineError.promptEncodeFailed
            default: try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /// Re-blend the cached per-prompt embeddings with new weights.
    @discardableResult
    public func reblend(_ weights: [Float]) -> Bool {
        weights.withUnsafeBufferPointer { engine.reblendPrompts($0.baseAddress!, Int32($0.count)) }
    }

    // MARK: PCA + audio prompts

    @discardableResult
    public func loadPCA(_ path: String) -> Bool { path.withCString { engine.loadPcaFile($0) } }
    public var isPCALoaded: Bool { engine.isPcaLoaded() }
    public var pcaComponentCount: Int { Int(engine.pcaComponentCount()) }

    public func setAudioPrompt(index: Int, filename: String, samples: [Float]) {
        samples.withUnsafeBufferPointer { buf in
            filename.withCString { engine.setAudioPromptSamples(Int32(index), $0, buf.baseAddress!, buf.count) }
        }
    }
    public func setAudioEmbedding(index: Int, _ embedding: [Float]) {
        embedding.withUnsafeBufferPointer { engine.setAudioEmbedding(Int32(index), $0.baseAddress!) }
    }

    // MARK: State

    public func resetToFactory() { engine.resetToFactory() }
    @discardableResult
    public func saveState(_ path: String) -> Bool { path.withCString { engine.saveState($0) } }
    @discardableResult
    public func loadState(_ path: String) -> Bool { path.withCString { engine.loadState($0) } }

    // MARK: Generation

    /// Generate `frames` stereo frames (each `frameSamples` samples @ 48 kHz).
    public func generate(frames: Int) throws -> StereoBuffer {
        guard engine.isLoaded() else { throw EngineError.notLoaded }
        let n = MagentaRTConstants.frameSamples
        var left = [Float](repeating: 0, count: frames * n)
        var right = [Float](repeating: 0, count: frames * n)

        // Generate directly into the destination buffers (no per-frame temp +
        // copy). The pointers stay valid for the synchronous loop.
        var failedFrame = -1
        left.withUnsafeMutableBufferPointer { lp in
            right.withUnsafeMutableBufferPointer { rp in
                let lb = lp.baseAddress!, rb = rp.baseAddress!
                for f in 0..<frames {
                    if !engine.generateFrame(lb + f * n, rb + f * n) {
                        failedFrame = f
                        break
                    }
                }
            }
        }
        if failedFrame >= 0 { throw EngineError.generateFailed(frame: failedFrame) }
        return StereoBuffer(left: left, right: right)
    }

    /// Timing of the most recent generated frame.
    public var lastFrameMilliseconds: Float { engine.lastTimings().total_ms }
}
