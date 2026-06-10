# MagentaRT

Swift bridge to the Magenta RealTime 2 C++ inference engine (`magentart::core`,
MLX on Metal), consumed via Swift/C++ interop from a prebuilt xcframework.

- `Sources/MagentaRT` — engine API (`OfflineEngine`, `RealtimeEngine`,
  `RealtimeControls`, `HFCache`, `WAVWriter`).
- `Sources/MagentaRTPlayer` — `MagentaPlayer` (AVAudioEngine streaming) + `LevelMeter`.
- `Tools/{mrt-cli,mrt-play}` — CLI tools. `Examples/MagentaRTDemo` — SwiftUI app
  (Explore + Jam) and the app-hosted engine tests (`MagentaRTDemoTests`).
- `Frameworks/Magentart.xcframework` (+ `mlx.metallib`) — prebuilt by
  `../../cpp/magentart-xcframework-builder` (`make`); gitignored.

## Running / testing

MLX loads `mlx.metallib` colocated with the binary. Build/run via **Xcode** or
`scripts/run.sh` (which copies the metallib next to the `swift build` binary) —
bare `swift run`/`swift test` won't find it. Engine code can't run under
`swift test` (TFLite weak-symbol coalescing crashes in a `.xctest` bundle);
verify the engine via the CLIs or the **app-hosted** `MagentaRTDemoTests`
(`xcodebuild test -scheme MagentaRTDemo`).

## Documentation

`MagentaRT` / `MagentaRTPlayer` ship DocC-generated reference docs (see
`Sources/*/Documentation.docc/` and `Scripts/build_docs.sh`). **`///` doc
comments on public symbols are published** to https://mnmly.github.io/MagentaRT/
and (with `EMIT_LLMS_TXT=1`) into `docs/llms.txt`.

When you add or modify a `public` declaration:

- Write a `///` comment: one-sentence summary, then a paragraph only if the *why*
  is non-obvious. Don't restate the signature.
- Document parameters with `- Parameter name:` using the **internal** name when
  there's an external label (DocC warns otherwise).
- Cross-reference with double-backtick links, e.g. `` ``RealtimeControls/setBlendWeights(_:)`` ``.
  DocC links are signature-sensitive: `foo(_:)` ≠ `foo(_:_:)`.
- File new top-level symbols under the right `## Topics` group (by *user task*)
  in `Sources/<Target>/Documentation.docc/<Target>.md`.

Verify:

```bash
Scripts/build_docs.sh        # expect exit 0, no new "doesn't exist" / "external name" warnings
```
