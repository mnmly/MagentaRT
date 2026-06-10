# MagentaRT

A Swift bridge to the **Magenta RealTime 2** C++ inference engine
(`magentart::core`, MLX on Metal), with a clean Swift-6 concurrency surface and
an `AVAudioEngine` realtime player. Built on top of a prebuilt
`Magentart.xcframework` consumed via Swift/C++ interoperability — **not** a
reimplementation of the model in mlx-swift (which would give no performance win,
since both drive the same MLX Metal kernels).

## Layout

| Target | What |
|---|---|
| `MagentartCore` | binaryTarget → `Frameworks/Magentart.xcframework` (the C++ stack + facade) |
| `MagentaRT` | Swift API: `OfflineEngine` actor, `RealtimeEngine` actor, controls/render handles, WAV writer |
| `MagentaRTPlayer` | `MagentaPlayer` — AVAudioEngine realtime streaming |
| `Tools/mrt-cli` | CLI: offline generate → WAV (port of `hello_mrt2`) |
| `Tools/mrt-play` | CLI: live streaming demo |
| `Examples/MagentaRTDemo` | SwiftUI app — live demo with prompt + sampling controls + meter (see [Examples/README.md](Examples/README.md)) |

## Setup

1. Build & mirror the xcframework with
   [`magentart-xcframework-builder`](../../cpp/magentart-xcframework-builder)
   (its `config.sh` mirrors into this package's `Frameworks/`).
2. `swift build` to compile.
3. Download model assets (once): `mrt models init && mrt models download`
   → `~/Documents/Magenta/magenta-rt-v2/`.

## ⚠️ Running needs Xcode (mlx.metallib)

MLX locates `mlx.metallib` at runtime *next to the binary*. **Run `mrt-cli` /
`mrt-play` through an Xcode app/test target** (which bundles `mlx.metallib` from
`Frameworks/`), not bare `swift run` — the CLI will otherwise fail to initialize
Metal. `swift build`/`swift test` are fine for compiling and non-MLX tests.

## Concurrency design

- **`OfflineEngine` / `RealtimeEngine` are actors** on a dedicated serial
  executor (`DispatchSerialQueue`), so the blocking C++ load/generate calls run
  on a private thread instead of starving the cooperative pool. They are the
  sole owners of the non-Sendable C++ engines.
- **Atomic, lock-free C++ setters** (temperature, top-k, CFG, MIDI, volume) are
  surfaced via `RealtimeControls` — an `@unchecked Sendable` handle callable from
  the UI without an actor hop. Invariant: it only touches the engine's atomic
  setters.
- **The audio render block is nonisolated.** `MagentaPlayer`'s
  `AVAudioSourceNode` render block runs on the CoreAudio render thread and calls
  `RealtimeRenderHandle.read` (→ lock-free `read_audio_stereo`) directly — no
  `await`, no allocation, no actor hop. The C++ engine is a foreign *reference
  type* (stable address), so the handle carries it safely. Lifetime ordering
  guarantees no render call races teardown: `start()` starts the inference loop
  before audio; `stop()` stops audio before the inference loop.

## Example

```swift
// Offline
let engine = OfflineEngine()
try await engine.initAssets(resourceDir: resources)
try await engine.loadModel(mlxfnPath)
try await engine.setTextPrompt("disco funk")
let audio = try await engine.generate(frames: 100)   // 4 s
try WAVWriter.write(audio, to: URL(fileURLWithPath: "out.wav"))

// Realtime
let player = MagentaPlayer()
try await player.load(model: mlxfnPath, resources: resources)
try await player.setPrompt("disco funk")
try await player.start()
player.controls?.setTemperature(1.2)   // lock-free, no actor hop
```
