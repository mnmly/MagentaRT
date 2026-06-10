# ``MagentaRT``

A Swift bridge to the Magenta RealTime 2 C++ inference engine (MLX on Metal).

## Overview

`MagentaRT` wraps `magentart::core` — the C++ engine that runs the Magenta
RealTime 2 model on Apple Silicon — behind a Swift-6 concurrency API. Two
engines cover the two modes: ``OfflineEngine`` generates audio frame-by-frame
(e.g. to a WAV file), and ``RealtimeEngine`` streams continuously while you
change prompts and parameters live.

Each engine is an `actor` that owns the non-`Sendable` C++ engine and runs on a
dedicated serial executor. Lock-free, audio-thread-safe parameter and note
control is surfaced through ``RealtimeControls``; the realtime audio thread pulls
samples through ``RealtimeRenderHandle`` (used by `MagentaRTPlayer`).

```swift
// Offline: prompt → 4 seconds of audio → WAV
let engine = OfflineEngine()
try await engine.initAssets(resourceDir: HFCache.resourcesPath()!)
try await engine.loadModel(HFCache.modelPath()!)
try await engine.setTextPrompt("disco funk")
let audio = try await engine.generate(frames: 100)          // 100 frames = 4 s
try WAVWriter.write(audio, to: URL(fileURLWithPath: "out.wav"))
```

> Important: At runtime MLX loads `mlx.metallib` colocated with the executable.
> Build/run via Xcode or `scripts/run.sh`; bare `swift run` won't place it. See
> the package README.

## Topics

### Generating audio offline

- ``OfflineEngine``
- ``WAVWriter``

### Streaming in real time

- ``RealtimeEngine``
- ``RealtimeControls``
- ``RealtimeRenderHandle``

### Locating model assets

- ``HFCache``

### Model constants

- ``MagentaRTConstants``
