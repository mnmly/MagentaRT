# ``MagentaRTPlayer``

Stream Magenta RealTime 2 audio live through `AVAudioEngine`.

## Overview

``MagentaPlayer`` drives a `RealtimeEngine` (from `MagentaRT`) through an
`AVAudioSourceNode`. Lifecycle and prompt changes go through the engine actor,
while the realtime render block pulls audio on the CoreAudio render thread with
no `await`, allocation, or actor hop — the crux of the realtime-safe design.
``LevelMeter`` exposes the live output RMS for a UI meter.

```swift
let player = MagentaPlayer()
try await player.load(model: modelPath, resources: resourcesPath)
try await player.setPrompt("disco funk")
try await player.start()
player.controls?.setTemperature(1.2)        // lock-free, no actor hop
// later, on quit:
await player.stop()                         // stops audio before the engine
```

> Important: `start()` begins the inference loop before the audio engine, and
> `stop()` stops the audio engine before the inference loop, so a render call can
> never race lifecycle teardown.

## Topics

### Playing audio

- ``MagentaPlayer``

### Metering

- ``LevelMeter``
