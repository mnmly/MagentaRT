//
//  ContentView.swift
//  MagentaRTDemo
//
//  Live realtime demo driving MagentaPlayer: load a model, set a prompt, stream
//  audio, and tweak sampling parameters through the lock-free RealtimeControls
//  while a buffer/throughput meter updates from the engine metrics.
//
//  Model/resources paths auto-resolve from the HuggingFace cache (populated by
//  scripts/download-models.sh) and can be overridden with the folder pickers;
//  selections persist via @AppStorage.
//

import SwiftUI
import UniformTypeIdentifiers
import MagentaRT
import MagentaRTPlayer

// `HFCache` (HuggingFace cache resolution) comes from the MagentaRT library.

@MainActor
@Observable
final class DemoModel {
    /// The live model, so the app delegate can stop streaming on quit.
    static weak var current: DemoModel?

    init() { Self.current = self }

    enum Phase: String { case idle = "Idle", loading = "Loading…", streaming = "Streaming", error = "Error" }
    var phase: Phase = .idle
    var detail = ""

    var bufferFill = 0.0
    var frameMs: Float = 0
    var droppedFrames: UInt64 = 0

    var temperature: Double = 1.2
    var topK: Double = 40
    var cfgMusiccoca: Double = 3.0
    var cfgNotes: Double = 4.0       // how strongly held notes steer generation
    var blend: Double = 0.5          // A↔B crossfade (0 = all A, 1 = all B)
    var drumless = false
    /// Ring-buffer size in samples. The engine default (2048 ≈ 1 frame) is tight
    /// and can underrun → clicks; 4096 doubles the headroom (~85 ms latency).
    var bufferSamples = 4096

    // Jam (note control)
    var midiGate = true              // silence output when no notes are held
    var solo = false                 // auto-stop after `soloTimeout` of no notes
    var activeNotes: Set<Int> = []
    let soloTimeout: TimeInterval = 30
    private var lastNoteActivity = Date.distantPast

    var isStreaming: Bool { phase == .streaming }
    var isBusy: Bool { phase == .loading }

    /// Live output RMS for the meter (read on the UI's display tick).
    var outputLevel: Float { player?.meter.rms ?? 0 }

    private var player: MagentaPlayer?
    private var metricsTask: Task<Void, Never>?

    func start(model: String, resources: String, promptA: String, promptB: String) async {
        guard !isStreaming else { return }
        phase = .loading
        do {
            let p = MagentaPlayer()
            detail = "loading model…"
            try await p.load(model: model, resources: resources)
            detail = "encoding prompts…"
            try await p.setPrompts(weightedPrompts(promptA, promptB))
            try await p.start()
            player = p
            p.controls?.setBufferSize(bufferSamples)   // headroom against clicks
            applyControls()
            applyBlend()
            lastNoteActivity = Date()
            phase = .streaming; detail = ""
            startMetrics()
        } catch {
            phase = .error; detail = "\(error)"
        }
    }

    func stop() async {
        metricsTask?.cancel(); metricsTask = nil
        await player?.stop()
        player = nil
        phase = .idle; detail = ""
        bufferFill = 0; frameMs = 0; droppedFrames = 0
    }

    /// Re-encode both prompts (used when the user edits prompt text live).
    func setPrompts(_ a: String, _ b: String) {
        guard let player else { return }
        Task { try? await player.setPrompts(weightedPrompts(a, b)) }
    }

    private func weightedPrompts(_ a: String, _ b: String) -> [(text: String, weight: Float)] {
        var out: [(text: String, weight: Float)] = []
        if !a.isEmpty { out.append((a, 1)) }
        if !b.isEmpty { out.append((b, 1)) }
        return out
    }

    /// Live crossfade between the two prompt slots (lock-free, no actor hop).
    func applyBlend() {
        player?.controls?.setBlendWeights([Float(1 - blend), Float(blend)])
    }

    func reset() { player?.controls?.triggerReset() }

    func applyBufferSize() { player?.controls?.setBufferSize(bufferSamples) }

    func applyControls() {
        guard let c = player?.controls else { return }
        c.setTemperature(Float(temperature))
        c.setTopK(Int(topK))
        c.setCfgMusiccoca(Float(cfgMusiccoca))
        c.setDrumless(drumless)
        // NOTE: the MIDI gate is NOT applied here — it's a Jam-only setting. On
        // Explore the gate stays off (continuous playback); JamView calls
        // applyNoteControls() itself after starting so notes gate the output.
    }

    // MARK: Note control (Jam)

    /// MIDI gate + note conditioning strength (both lock-free).
    func applyNoteControls() {
        guard let c = player?.controls else { return }
        c.setMidiGateEnabled(midiGate)
        c.setCfgNotes(Float(cfgNotes))
    }

    func noteOn(_ n: Int) {
        guard activeNotes.insert(n).inserted else { return }
        player?.controls?.noteOn(n)
        lastNoteActivity = Date()
    }

    func noteOff(_ n: Int) {
        guard activeNotes.remove(n) != nil else { return }
        player?.controls?.noteOff(n)
    }

    func allNotesOff() {
        for n in activeNotes { player?.controls?.noteOff(n) }
        activeNotes.removeAll()
    }

    private func startMetrics() {
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { break }
                let m = await player.metrics()
                self.bufferFill = m.bufferCapacity > 0
                    ? Double(m.bufferAvailable) / Double(m.bufferCapacity) : 0
                self.frameMs = m.totalMs
                self.droppedFrames = m.droppedFrames

                // SOLO: auto-stop after a stretch of no note activity.
                if self.solo, self.activeNotes.isEmpty,
                   Date().timeIntervalSince(self.lastNoteActivity) > self.soloTimeout {
                    await self.stop()
                    break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

struct ExploreView: View {
    @Bindable var model: DemoModel
    @AppStorage("mrt.modelName") private var modelName = "mrt2_small"
    @AppStorage("mrt.modelPath") private var modelPath = ""
    @AppStorage("mrt.resourcesPath") private var resourcesPath = ""
    @AppStorage("mrt.promptA") private var promptA = "disco funk"
    @AppStorage("mrt.promptB") private var promptB = "ambient piano"

    @State private var downloader = Downloader()
    @State private var pickingModel = false
    @State private var pickingResources = false
    @State private var downloadError = ""

    private var canPlay: Bool { !modelPath.isEmpty && !resourcesPath.isEmpty }

    var body: some View {
        Form {
            Section("Assets") {
                Picker("Model", selection: $modelName) {
                    Text("small · 230M").tag("mrt2_small")
                    Text("base · 2.4B").tag("mrt2_base")
                }
                .pickerStyle(.segmented)
                .onChange(of: modelName) { _, name in
                    // Re-resolve from the HF cache for the newly selected size.
                    modelPath = HFCache.modelPath(name) ?? ""
                    if resourcesPath.isEmpty { resourcesPath = HFCache.resourcesPath() ?? "" }
                }
                if modelName == "mrt2_base" {
                    Text("base needs a Pro/Max chip for real-time (M-series).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                pathRow("Model (.mlxfn)", text: $modelPath) { pickingModel = true }
                pathRow("Resources folder", text: $resourcesPath) { pickingResources = true }

                if downloader.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: downloader.progress)
                        Text(downloader.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    HStack {
                        Button {
                            Task { await runDownload() }
                        } label: {
                            Label("Download \(modelName)", systemImage: "arrow.down.circle")
                        }
                        if !canPlay {
                            Text("…or pick existing files with Browse")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !downloadError.isEmpty {
                    Text(downloadError).font(.caption).foregroundStyle(.red)
                }
            }
            .disabled(model.isStreaming)

            Section("Prompts") {
                TextField("Prompt A", text: $promptA).onSubmit { model.setPrompts(promptA, promptB) }
                TextField("Prompt B", text: $promptB).onSubmit { model.setPrompts(promptA, promptB) }
                HStack {
                    Button("Set") { model.setPrompts(promptA, promptB) }.disabled(!model.isStreaming)
                    Spacer()
                    Text("blend").font(.caption).foregroundStyle(.secondary)
                }
                // Live crossfade A↔B via the lock-free blend weights.
                HStack {
                    Text("A").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.blend, in: 0...1) { _ in model.applyBlend() }
                    Text("B").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Sampling") {
                slider("Temperature", $model.temperature, 0.1...2.0, "%.2f")
                slider("Top-k", $model.topK, 1...256, "%.0f")
                slider("CFG (style)", $model.cfgMusiccoca, 0...8, "%.1f")
                Toggle("Drumless", isOn: $model.drumless)
                    .onChange(of: model.drumless) { _, on in model.applyControls() }
                Picker("Audio buffer", selection: $model.bufferSamples) {
                    Text("2048 · low latency").tag(2048)
                    Text("4096 · balanced").tag(4096)
                    Text("8192 · safest").tag(8192)
                }
                .onChange(of: model.bufferSamples) { _, _ in model.applyBufferSize() }
                Button("Reset state") { model.reset() }.disabled(!model.isStreaming)
            }

            Section("Metrics") {
                ProgressView(value: model.bufferFill) { Text("Buffer \(Int(model.bufferFill * 100))%") }
                LabeledContent("Frame", value: String(format: "%.1f ms (real-time ≤ 40)", model.frameMs))
                LabeledContent("Dropped frames", value: "\(model.droppedFrames)")
            }

            Section {
                Button {
                    Task {
                        if model.isStreaming { await model.stop() }
                        else { await model.start(model: modelPath, resources: resourcesPath, promptA: promptA, promptB: promptB) }
                    }
                } label: {
                    Label(model.isStreaming ? "Stop" : "Play",
                          systemImage: model.isStreaming ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(model.isStreaming ? .red : .accentColor)
                .disabled(model.isBusy || !canPlay)

                if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(.caption)
                        .foregroundStyle(model.phase == .error ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .navigationTitle("Magenta RealTime")
        .onAppear {
            // First launch: prefill from the HuggingFace cache if available.
            if modelPath.isEmpty { modelPath = HFCache.modelPath(modelName) ?? "" }
            if resourcesPath.isEmpty { resourcesPath = HFCache.resourcesPath() ?? "" }
        }
        .fileImporter(isPresented: $pickingModel, allowedContentTypes: [.item]) {
            if case .success(let url) = $0 { modelPath = url.path }
        }
        .fileImporter(isPresented: $pickingResources, allowedContentTypes: [.folder]) {
            if case .success(let url) = $0 { resourcesPath = url.path }
        }
    }

    private func runDownload() async {
        downloadError = ""
        do {
            let (m, r) = try await downloader.download(model: modelName)
            modelPath = m
            resourcesPath = r
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func pathRow(_ label: String, text: Binding<String>, browse: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(label, text: text)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button("Browse…", action: browse)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: fmt, value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range) { editing in if !editing { model.applyControls() } }
        }
    }
}

#Preview {
    ExploreView(model: DemoModel())
}
