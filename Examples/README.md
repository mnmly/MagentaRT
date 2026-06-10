# Examples

## MagentaRTDemo (SwiftUI app)

A live realtime demo driving `MagentaPlayer` from `MagentaRTPlayer`, with two
tabs over one shared engine:

- **Explore** — set **two prompts** and **crossfade between them live**
  (multi-prompt + lock-free blend weights), toggle **drumless**, hit **reset**,
  tweak sampling (temperature / top-k / CFG); buffer + frame-time meter.
- **Jam** (port of `examples/jam`) — play the model like an instrument: a
  **piano keyboard** (tap/drag) and **computer-keyboard MIDI** (A S D F… , Z/X
  octave) gate the output via the MIDI-gate envelope, over a texture prompt, with
  a **note-influence (cfgNotes)** slider, **SOLO** auto-stop, and an **output
  level meter** (RMS off the realtime render path). All note/param control is
  lock-free `RealtimeControls`.

### Getting the model

Three ways, pick one:

- **In-app**: hit **Download mrt2_small** (pure-Swift HuggingFace download into
  Application Support; no Python needed). Paths fill in automatically.
- **Script**: `../scripts/download-models.sh [mrt2_small|mrt2_base]` downloads
  into the HuggingFace cache (`~/.cache/huggingface`). The app auto-resolves it
  on launch (reads `refs/main` → `snapshots/<sha>/`).
- **Browse**: point the **Model (.mlxfn)** / **Resources folder** pickers at an
  existing download (e.g. `~/Documents/Magenta/magenta-rt-v2/`).

Picked paths persist via `@AppStorage`. Gated repo? `hf auth login` / set
`HF_TOKEN` before the script.

### Project settings (already configured)

These are set in the checked-in project; listed for reference:

- **`SWIFT_OBJC_INTEROP_MODE = objcxx`** — C++ interop, required because the app
  links `MagentaRT`/`MagentaRTPlayer` (SPM propagates the C++-interop requirement).
- **`ENABLE_APP_SANDBOX = NO`** — so the app can read model files from `~`. (For
  a sandboxed/distributable build, re-enable it and switch the pickers to
  security-scoped bookmarks.)
- **"Copy mlx.metallib" build phase** — copies `Frameworks/mlx.metallib` next to
  the executable (MLX's colocated lookup) and codesigns it so the bundle seal
  succeeds. (`ENABLE_USER_SCRIPT_SANDBOXING = NO` lets the script reach the
  package's `Frameworks/`.)

### Run

Build the xcframework first (`make` in `magentart-xcframework-builder`, which
mirrors `Magentart.xcframework` + `mlx.metallib` into the package's
`Frameworks/`). Then open `MagentaRTDemo.xcodeproj`, **Run**, get the model, hit
**Play**.

## Engine unit tests (`MagentaRTDemoTests`)

Engine code (TFLite/MLX) **can't** be tested via SwiftPM `swift test` — the merged
static lib linked into a `.xctest` *bundle* mis-resolves Eigen's weak GEMM symbols
and crashes. So the tests are an **app-hosted** target (`MagentaRTDemoTests`, Test
Host = `MagentaRTDemo`): the engine runs in the app's executable image (correct
linking) and the host bundles `mlx.metallib`, so both the MusicCoCa encode and
real MLX generation work. Run with **⌘U** or:

```sh
xcodebuild test -scheme MagentaRTDemo -destination 'platform=macOS'
```

`EngineTests` covers the prompt encode and a non-silent generation assertion;
both skip cleanly if no model is cached (run `../scripts/download-models.sh`
first). The test target needs **C++/Objective-C interop = C++/Objective-C++** and
a dependency on the `MagentaRT` package product (set when the target is created).

## CLI tools

`mrt-cli` (offline → WAV) and `mrt-play` (live streaming) live in `../Tools/` and
run from the command line via `../scripts/run.sh` (which colocates the metallib
next to the `swift build` binary — no Xcode project needed):

```sh
scripts/run.sh mrt-cli  --model <mlxfn> --prompt "disco funk" --out out.wav
scripts/run.sh mrt-play --model <mlxfn> --prompt "disco funk" --duration 20
```
