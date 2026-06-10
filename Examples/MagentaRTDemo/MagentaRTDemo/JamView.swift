//
//  JamView.swift
//  MagentaRTDemo
//
//  Play the model like an instrument: a piano keyboard + computer-keyboard MIDI
//  gate the streaming output (MIDI-gate envelope), over a texture prompt, with a
//  "note influence" (cfgNotes) control, SOLO auto-stop, and an output meter.
//

import SwiftUI

struct JamView: View {
    @Bindable var model: DemoModel
    @AppStorage("mrt.modelPath") private var modelPath = ""
    @AppStorage("mrt.resourcesPath") private var resourcesPath = ""
    @AppStorage("mrt.jamPrompt") private var jamPrompt = "solo piano"

    @State private var octaveBase = 60          // C4
    private enum Field: Hashable { case keys, prompt }
    @FocusState private var focus: Field?

    // Computer keyboard → semitone (Ableton layout); Z / X shift the octave.
    private static let keyToSemitone: [Character: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7,
        "y": 8, "h": 9, "u": 10, "j": 11, "k": 12, "o": 13, "l": 14, "p": 15, ";": 16,
    ]

    private var canPlay: Bool { !modelPath.isEmpty && !resourcesPath.isEmpty }

    var body: some View {
        VStack(spacing: 14) {
            transport
            controls
            TimelineView(.animation) { _ in
                LevelBar(level: model.isStreaming ? model.outputLevel : 0)
            }
            .frame(height: 10)

            PianoKeyboardView(
                firstMidi: octaveBase - 12, octaves: 2, active: model.activeNotes,
                onNoteOn: model.noteOn, onNoteOff: model.noteOff
            )
            .frame(height: 170)

            Text("Computer keys: A S D F G H J = white · W E T Y U = black · Z / X = octave")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .keys)
        .onKeyPress(phases: [.down, .up]) { handleKey($0) }
        .onAppear { focus = .keys }
        .onDisappear { model.allNotesOff() }
        .navigationTitle("Jam")
    }

    private var transport: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Texture prompt", text: $jamPrompt)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .prompt)
                    .onSubmit {
                        if model.isStreaming { model.setPrompts(jamPrompt, "") }
                        focus = .keys          // hand focus back to the keyboard
                    }
                Button(model.isStreaming ? "Stop" : "Play") {
                    Task {
                        if model.isStreaming { await model.stop() }
                        else {
                            await model.start(model: modelPath, resources: resourcesPath,
                                              promptA: jamPrompt, promptB: "")
                            model.applyNoteControls()   // enable the note gate for Jam
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isStreaming ? .red : .accentColor)
                .disabled(model.isBusy || !canPlay)
            }
            if !canPlay {
                Text("Load a model in the Explore tab first.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.phase == .error {
                Text(model.detail).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Toggle("Note gate", isOn: $model.midiGate)
                    .onChange(of: model.midiGate) { _, _ in model.applyNoteControls() }
                Toggle("Solo", isOn: $model.solo)
                Spacer()
                Stepper("Octave \(octaveBase / 12 - 1)", value: $octaveBase, in: 24...96, step: 12)
            }
            HStack {
                Text("Note influence")
                Slider(value: $model.cfgNotes, in: 0...5) { _ in model.applyNoteControls() }
                Text(String(format: "%.1f", model.cfgNotes)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Only play notes when the keyboard (not the prompt field) has focus, so
        // typing in the text field enters text instead of triggering notes.
        guard focus == .keys, model.isStreaming,
              let ch = press.characters.lowercased().first else { return .ignored }
        if ch == "z" {
            if press.phase == .down { octaveBase = max(24, octaveBase - 12); model.allNotesOff() }
            return .handled
        }
        if ch == "x" {
            if press.phase == .down { octaveBase = min(96, octaveBase + 12); model.allNotesOff() }
            return .handled
        }
        guard let semi = Self.keyToSemitone[ch] else { return .ignored }
        let note = octaveBase + semi
        switch press.phase {
        case .down: model.noteOn(note)
        case .up: model.noteOff(note)
        default: break
        }
        return .handled
    }
}

/// Simple output level bar driven by the realtime RMS meter.
struct LevelBar: View {
    let level: Float
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.green.gradient)
                    .frame(width: g.size.width * CGFloat(min(1, max(0, level) * 4)))
            }
        }
    }
}
