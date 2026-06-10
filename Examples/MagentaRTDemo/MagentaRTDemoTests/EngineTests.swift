//
//  EngineTests.swift
//  MagentaRTDemoTests
//
//  App-HOSTED engine tests. These must run hosted by the MagentaRTDemo app
//  (Test Host = MagentaRTDemo): the engine's heavy C++ deps (TFLite/Eigen/MLX)
//  link correctly into the app's executable image, and the app bundles
//  mlx.metallib — so both the MusicCoCa encode AND MLX generation work here,
//  where a plain SwiftPM `swift test` bundle crashes (weak-symbol coalescing).
//
//  All tests skip cleanly if no model assets are cached
//  (run ../scripts/download-models.sh first).
//

import Testing
import Foundation
import MagentaRT

@MainActor
struct EngineTests {

    /// MusicCoCa text encode (TFLite/CPU) — the exact path that SIGSEGVs in a
    /// SwiftPM test bundle but is fine in a real/host executable.
    @Test func encodesPrompts() async throws {
        guard let resources = HFCache.resourcesPath() else { return }
        let engine = OfflineEngine()
        try await engine.initAssets(resourceDir: resources)
        try await engine.setPrompts([("disco", 0.7), ("funk", 0.3)])
        try await engine.setTextPrompt("a jazz piano trio")
    }

    /// Full generation through MLX/Metal → assert real (non-silent) audio.
    @Test func generatesNonSilentAudio() async throws {
        guard let model = HFCache.modelPath(), let resources = HFCache.resourcesPath() else { return }
        let engine = OfflineEngine()
        try await engine.initAssets(resourceDir: resources)
        try await engine.loadModel(model)
        try await engine.setTextPrompt("disco funk")

        let frames = 10                         // 0.4 s
        let buffer = try await engine.generate(frames: frames)
        #expect(buffer.left.count == frames * MagentaRTConstants.frameSamples)
        #expect(buffer.right.count == buffer.left.count)

        let peak = buffer.left.reduce(Float(0)) { Swift.max($0, abs($1)) }
        #expect(peak > 0.001, "expected audible output, got peak \(peak)")
    }
}
