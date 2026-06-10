//
//  PianoKeyboardView.swift
//  MagentaRTDemo
//
//  A tap/drag piano. Press or drag across keys to play (monophonic glissando
//  via mouse); chords come from the computer keyboard in JamView. Highlights
//  the engine's active notes.
//

import SwiftUI

struct PianoKeyboardView: View {
    let firstMidi: Int            // a C (e.g. 48 = C3)
    let octaves: Int
    let active: Set<Int>
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    @State private var dragNote: Int?

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]   // C D E F G A B
    // White-key index (within octave) → semitone of the black key that follows it.
    private static let blackAfter: [Int: Int] = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]

    private var whiteNotes: [Int] {
        (0..<octaves).flatMap { o in Self.whiteOffsets.map { firstMidi + o * 12 + $0 } }
    }
    // (midi, global white index it sits to the right of)
    private var blackNotes: [(midi: Int, after: Int)] {
        (0..<octaves).flatMap { o -> [(Int, Int)] in
            Self.blackAfter.map { (whiteIdx, semi) in
                (firstMidi + o * 12 + semi, o * 7 + whiteIdx)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(whiteNotes.count)
            let h = geo.size.height
            let bw = w * 0.62
            let bh = h * 0.6

            ZStack(alignment: .topLeading) {
                // White keys
                HStack(spacing: 1) {
                    ForEach(whiteNotes, id: \.self) { note in
                        key(note, isBlack: false)
                    }
                }
                // Black keys
                ForEach(blackNotes, id: \.midi) { b in
                    key(b.midi, isBlack: true)
                        .frame(width: bw, height: bh)
                        .offset(x: CGFloat(b.after + 1) * w - bw / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let n = noteAt(g.location, w: w, bw: bw, bh: bh)
                        if n != dragNote {
                            if let old = dragNote { onNoteOff(old) }
                            if let n { onNoteOn(n) }
                            dragNote = n
                        }
                    }
                    .onEnded { _ in
                        if let n = dragNote { onNoteOff(n) }
                        dragNote = nil
                    }
            )
        }
    }

    private func key(_ note: Int, isBlack: Bool) -> some View {
        let on = active.contains(note)
        return RoundedRectangle(cornerRadius: isBlack ? 3 : 4)
            .fill(on ? Color.accentColor
                     : (isBlack ? Color.black : Color.white))
            .overlay(RoundedRectangle(cornerRadius: isBlack ? 3 : 4)
                .stroke(.gray.opacity(0.4), lineWidth: 0.5))
            .frame(maxWidth: isBlack ? nil : .infinity, maxHeight: .infinity)
    }

    /// Resolve the note under a point: black keys (on top) first, then white.
    private func noteAt(_ p: CGPoint, w: CGFloat, bw: CGFloat, bh: CGFloat) -> Int? {
        if p.y <= bh {
            for b in blackNotes {
                let cx = CGFloat(b.after + 1) * w
                if abs(p.x - cx) <= bw / 2 { return b.midi }
            }
        }
        let idx = Int(p.x / w)
        guard idx >= 0, idx < whiteNotes.count else { return nil }
        return whiteNotes[idx]
    }
}
