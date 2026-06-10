// mrt-play — live streaming demo. Loads a model, sets a prompt, and streams
// generated audio through CoreAudio for `--duration` seconds, printing the
// ring-buffer metrics each second.
//
// Run via Xcode/xcodebuild so mlx.metallib is bundled (see README).
//
//   mrt-play --model <mlxfn> [--resources <dir>] [--prompt "..."] [--duration 20]

import Foundation
import MagentaRT
import MagentaRTPlayer

@main
struct Main {
    struct Options {
        // Default to the HuggingFace cache (scripts/download-models.sh).
        var model = HFCache.modelPath() ?? ""
        var resources = HFCache.resourcesPath() ?? ""
        var prompt = "disco funk"
        var duration = 20.0
    }

    static func parse() -> Options {
        var o = Options()
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--model", "-m": o.model = it.next() ?? ""
            case "--resources", "-r": o.resources = it.next() ?? o.resources
            case "--prompt", "-p": o.prompt = it.next() ?? o.prompt
            case "--duration", "-d": o.duration = Double(it.next() ?? "") ?? o.duration
            case "--help", "-h":
                print("mrt-play --model <mlxfn> [--resources <dir>] [--prompt \"...\"] [--duration 20]")
                exit(0)
            default: FileHandle.standardError.write(Data("unknown arg: \(a)\n".utf8))
            }
        }
        return o
    }

    @MainActor
    static func main() async {
        let opts = parse()
        guard !opts.model.isEmpty, !opts.resources.isEmpty else {
            FileHandle.standardError.write(Data((
                "error: no model in the HuggingFace cache and --model/--resources not given.\n" +
                "       run scripts/download-models.sh, or pass --model/--resources.\n").utf8))
            exit(1)
        }
        do {
            let player = MagentaPlayer()
            print("loading \(opts.model)…")
            try await player.load(model: opts.model, resources: opts.resources)
            print("prompt: \"\(opts.prompt)\"")
            try await player.setPrompt(opts.prompt)

            print("streaming for \(opts.duration)s…")
            try await player.start()

            let ticks = Int(opts.duration)
            for _ in 0..<ticks {
                try await Task.sleep(for: .seconds(1))
                let m = await player.metrics()
                let fill = m.bufferCapacity > 0 ? 100 * m.bufferAvailable / m.bufferCapacity : 0
                print(String(format: "  buffer %3d%%  frame %.1f ms  dropped %d",
                             fill, m.totalMs, m.droppedFrames))
            }

            await player.stop()
            print("done.")
        } catch {
            FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
