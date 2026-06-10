import Foundation
import MagentartCore

/// Swift wrapper over the C++ `magentart::bridge::RealtimeEngine`
/// (`RealtimeRunner` underneath) for live streaming.
///
/// Concurrency design:
///  - This `actor` owns the C++ engine and serializes **lifecycle** (load,
///    start, stop, unload). It runs on a dedicated serial executor so blocking
///    C++ calls don't starve the global pool.
///  - Atomic, lock-free C++ setters are surfaced through `RealtimeControls`
///    (an `@unchecked Sendable` handle), callable from the UI without an actor
///    hop.
///  - The realtime audio render thread pulls samples through
///    `RealtimeRenderHandle` (also `@unchecked Sendable`), never touching the
///    actor. See `RealtimeRenderHandle` for the safety invariants.
///
/// Because the C++ engine is a foreign **reference type**, its address is
/// stable, so the same instance can be shared (by reference) between the actor,
/// the controls, and the render handle without copies or moves.
public actor RealtimeEngine {
    public enum EngineError: Error, CustomStringConvertible {
        case initAssetsFailed(String)
        case loadFailed(String)
        case promptEncodeFailed
        public var description: String {
            switch self {
            case .initAssetsFailed(let d): return "init_assets failed: \(d)"
            case .loadFailed(let p): return "load failed: \(p)"
            case .promptEncodeFailed: return "MusicCoCa text encode failed"
            }
        }
    }

    private let queue = DispatchSerialQueue(label: "com.mnmly.magentart.realtime")
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private let engine = magentart.bridge.RealtimeEngine.create()

    public init() {}

    // MARK: Lifecycle

    public func initAssets(resourceDir: String) throws {
        let ok = resourceDir.withCString { engine.initAssets($0) }
        guard ok else { throw EngineError.initAssetsFailed(resourceDir) }
    }

    public func loadModel(_ mlxfnPath: String) throws {
        let ok = mlxfnPath.withCString { engine.loadModel($0) }
        guard ok else { throw EngineError.loadFailed(mlxfnPath) }
    }

    public var isLoaded: Bool { engine.isLoaded() }

    /// Start the C++ inference thread (25 Hz). Call BEFORE starting audio so the
    /// ring buffers prime.
    public func start() { engine.start() }

    /// Stop the inference thread. Call AFTER the audio engine has stopped so no
    /// render call races teardown.
    public func stop() { engine.stop() }

    public func unload() { engine.unload() }

    // MARK: Prompt

    public func setTextPrompt(_ text: String) async throws {
        text.withCString { engine.setTextPrompt($0) }
        try await awaitEncode()
    }

    /// Set several weighted text prompts at once (blended via `RealtimeControls`
    /// blend weights). Awaits the MusicCoCa encode.
    public func setPrompts(_ prompts: [(text: String, weight: Float)]) async throws {
        engine.beginPrompts()
        for p in prompts { p.text.withCString { engine.addPrompt($0, p.weight) } }
        engine.commitPrompts()
        try await awaitEncode()
    }

    private func awaitEncode() async throws {
        while true {
            switch engine.textEncoderStatus() {   // 0 idle,1 fetching,2 ok,3 err
            case 2: return
            case 3: throw EngineError.promptEncodeFailed
            default: try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    // MARK: PCA prompt interpolation

    @discardableResult
    public func loadPCA(_ path: String) -> Bool { path.withCString { engine.loadPcaFile($0) } }
    public var isPCALoaded: Bool { engine.isPcaLoaded() }
    public var pcaComponentCount: Int { Int(engine.pcaComponentCount()) }
    public var pcaCentroidCount: Int { Int(engine.pcaCentroidCount()) }

    // MARK: Audio prompts

    /// Inject mono PCM into prompt slot `index` (encoded on the MusicCoCa worker).
    public func setAudioPrompt(index: Int, filename: String, samples: [Float]) {
        samples.withUnsafeBufferPointer { buf in
            filename.withCString { engine.setAudioPromptSamples(Int32(index), $0, buf.baseAddress!, buf.count) }
        }
    }
    /// Directly set a MusicCoCa embedding (768 floats) for slot `index`.
    public func setAudioEmbedding(index: Int, _ embedding: [Float]) {
        embedding.withUnsafeBufferPointer { engine.setAudioEmbedding(Int32(index), $0.baseAddress!) }
    }

    // MARK: Reset / state

    /// Full reset: stops inference, resets model state, clears buffers, restarts.
    public func reset() { engine.reset() }
    /// Restore the factory initial state (undo prefill/load_state checkpoints).
    public func resetToFactory() { engine.resetToFactory() }
    @discardableResult
    public func saveState(_ path: String) -> Bool { path.withCString { engine.saveState($0) } }
    @discardableResult
    public func loadState(_ path: String) -> Bool { path.withCString { engine.loadState($0) } }

    // MARK: Handles for other threads

    /// A lock-free controls handle for the UI/automation thread.
    public func makeControls() -> RealtimeControls { RealtimeControls(engine) }

    /// A render handle for the CoreAudio render thread. The returned handle
    /// retains the engine; keep it alive for the lifetime of the audio graph.
    public func makeRenderHandle() -> RealtimeRenderHandle { RealtimeRenderHandle(engine) }

    /// Snapshot of runtime metrics (buffer level, frame timing, underruns).
    public func metrics() -> Metrics {
        let m = engine.metrics()
        return Metrics(
            transformerMs: m.transformer_ms,
            totalMs: m.total_ms,
            bufferAvailable: Int(m.buffer_available),
            bufferCapacity: Int(m.buffer_capacity),
            droppedFrames: m.dropped_frames
        )
    }

    public struct Metrics: Sendable {
        public let transformerMs: Float
        public let totalMs: Float
        public let bufferAvailable: Int
        public let bufferCapacity: Int
        public let droppedFrames: UInt64
    }
}

/// Lock-free parameter controls. Safe to call from any thread (the underlying
/// C++ setters are atomic), so the UI can drive parameters without hopping to
/// the engine actor.
///
/// `@unchecked Sendable` invariant: the only operations exposed are the C++
/// engine's **atomic** setters (`set_temperature`, `set_top_k`, `set_cfg_*`,
/// MIDI, volume…); no lifecycle or non-atomic state is touched here.
public final class RealtimeControls: @unchecked Sendable {
    private let engine: magentart.bridge.RealtimeEngine
    init(_ engine: magentart.bridge.RealtimeEngine) { self.engine = engine }

    public func setTemperature(_ t: Float) { engine.setTemperature(t) }
    public func setTopK(_ k: Int) { engine.setTopK(Int32(k)) }
    public func setCfgMusiccoca(_ v: Float) { engine.setCfgMusiccoca(v) }
    public func setCfgNotes(_ v: Float) { engine.setCfgNotes(v) }
    public func setCfgDrums(_ v: Float) { engine.setCfgDrums(v) }
    public func setVolumeDb(_ v: Float) { engine.setVolumeDb(v) }
    public func setMute(_ m: Bool) { engine.setMute(m) }
    public func noteOn(_ n: Int) { engine.setNoteOn(Int32(n)) }
    public func noteOff(_ n: Int) { engine.setNoteOff(Int32(n)) }
    public func setMidiGateEnabled(_ e: Bool) { engine.setMidiGateEnabled(e) }

    // Prompt blend (per slot, 0…1) and PCA interpolation coefficients.
    public func setBlendWeight(_ i: Int, _ w: Float) { engine.setBlendWeight(Int32(i), w) }
    public func setBlendWeights(_ weights: [Float]) {
        weights.withUnsafeBufferPointer { engine.setBlendWeights($0.baseAddress!, Int32($0.count)) }
    }
    public func setPcaCoeff(_ i: Int, _ v: Float) { engine.setPcaCoeff(Int32(i), v) }

    // Sampling extras + mode toggles (all atomic in C++).
    public func setUnmaskWidth(_ w: Int) { engine.setUnmaskWidth(Int32(w)) }
    public func setSeedRotation(_ r: Int) { engine.setSeedRotation(Int32(r)) }
    public func setDrumless(_ on: Bool) { engine.setDrumless(on) }
    public func setOnsetMode(_ mode: Int) { engine.setOnsetMode(Int32(mode)) }

    /// Rising-edge reset of the model state on the next frame (click-free).
    public func triggerReset() { engine.triggerReset() }

    /// Ring-buffer capacity in samples (latency vs glitch-resistance). The
    /// engine default is 2048 (~1 frame, tight); 4096/8192 add headroom. Atomic.
    public func setBufferSize(_ samples: Int) { engine.setBufferSize(samples) }
}

/// Realtime audio pull handle.
///
/// `@unchecked Sendable` + realtime-safety invariants:
///  1. `read(...)` maps to the C++ `read_audio_stereo` (lock-free, never
///     blocks, zero-pads on underrun) and must be called **only** on the
///     CoreAudio render thread.
///  2. It must be called **only between** `RealtimeEngine.start()` and
///     `RealtimeEngine.stop()`. The owner (e.g. `MagentaPlayer`) guarantees the
///     ordering: start inference → start audio; stop audio → stop inference, so
///     a render call can never race lifecycle teardown.
public final class RealtimeRenderHandle: @unchecked Sendable {
    private let engine: magentart.bridge.RealtimeEngine
    init(_ engine: magentart.bridge.RealtimeEngine) { self.engine = engine }

    /// Pull `count` stereo samples into `left`/`right`. Returns false on a ring
    /// buffer underrun (output is still written, zero-padded).
    @inline(__always)
    public func read(_ left: UnsafeMutablePointer<Float>,
                     _ right: UnsafeMutablePointer<Float>,
                     _ count: Int) -> Bool {
        engine.readAudioStereo(left, right, count)
    }
}
