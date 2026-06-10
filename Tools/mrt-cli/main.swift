// mrt-cli — offline generate → WAV. Swift port of examples/hello_mrt2/main.cpp.
//
// Run via Xcode/xcodebuild (so mlx.metallib bundles next to the binary). Bare
// `swift run` won't reliably place the metallib — see README.
//
//   mrt-cli --model <mlxfn> [--resources <dir>] [--prompt "..."]
//           [--frames N] [--out out.wav] [--temperature 1.0] [--top-k 100]

import Foundation
import MagentaRT

struct Options {
    // Default to the HuggingFace cache (scripts/download-models.sh); empty if
    // nothing is cached.
    var model = HFCache.modelPath() ?? ""
    var resources = HFCache.resourcesPath() ?? ""
    var prompt = "a jazz piano trio"
    var prompts = ""                       // multi: "text:weight,text:weight"
    var frames = 100                       // 100 frames = 4.0 s
    var out = "out.wav"
    var temperature: Float = 1.0
    var topK = 100
}

func parse() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    func next() -> String? { it.next() }
    while let a = next() {
        switch a {
        case "--model", "-m": o.model = next() ?? ""
        case "--resources", "-r": o.resources = next() ?? o.resources
        case "--prompt", "-p": o.prompt = next() ?? o.prompt
        case "--prompts": o.prompts = next() ?? o.prompts
        case "--frames", "-f": o.frames = Int(next() ?? "") ?? o.frames
        case "--out", "-o": o.out = next() ?? o.out
        case "--temperature", "-t": o.temperature = Float(next() ?? "") ?? o.temperature
        case "--top-k", "-k": o.topK = Int(next() ?? "") ?? o.topK
        case "--help", "-h":
            print("""
            mrt-cli --model <mlxfn> [--resources <dir>] [--prompt "..."]
                    [--frames N] [--out out.wav] [--temperature 1.0] [--top-k 100]
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown arg: \(a)\n".utf8))
        }
    }
    return o
}

let opts = parse()
guard !opts.model.isEmpty, !opts.resources.isEmpty else {
    FileHandle.standardError.write(Data((
        "error: no model in the HuggingFace cache and --model/--resources not given.\n" +
        "       run scripts/download-models.sh, or pass --model <mlxfn> --resources <dir>.\n").utf8))
    exit(1)
}

do {
    let engine = OfflineEngine()
    print("init assets: \(opts.resources)")
    try await engine.initAssets(resourceDir: opts.resources)
    print("load model:  \(opts.model)")
    try await engine.loadModel(opts.model)
    await engine.setSampling(temperature: opts.temperature, topK: opts.topK)

    if opts.prompts.isEmpty {
        print("prompt:      \"\(opts.prompt)\"  (encoding…)")
        try await engine.setTextPrompt(opts.prompt)
    } else {
        // "disco:0.7,funk:0.3" → weighted multi-prompt (exercises setPrompts).
        let parsed: [(text: String, weight: Float)] = opts.prompts.split(separator: ",").map {
            let kv = $0.split(separator: ":", maxSplits: 1)
            return (String(kv[0]), kv.count > 1 ? (Float(kv[1]) ?? 1) : 1)
        }
        print("prompts:     \(parsed)  (encoding…)")
        try await engine.setPrompts(parsed)
    }

    print("generating \(opts.frames) frames (\(Double(opts.frames) / 25.0) s)…")
    let start = Date()
    let buffer = try await engine.generate(frames: opts.frames)
    let elapsed = Date().timeIntervalSince(start)
    let msPerStep = elapsed / Double(opts.frames) * 1000
    print(String(format: "  %.1fs  (%.1f steps/s, %.1f ms/step; real-time = 40 ms/step)",
                 elapsed, Double(opts.frames) / elapsed, msPerStep))

    let url = URL(fileURLWithPath: opts.out)
    try WAVWriter.write(buffer, to: url)
    print("wrote \(url.path)  (\(buffer.sampleCount) samples/ch)")
} catch {
    FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
    exit(1)
}
