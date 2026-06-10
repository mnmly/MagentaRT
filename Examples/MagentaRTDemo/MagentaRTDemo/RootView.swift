//
//  RootView.swift
//  MagentaRTDemo
//
//  Owns the single shared engine model and switches between the prompt explorer
//  and the note-control "Jam" view. Both tabs drive the same MagentaPlayer.
//

import SwiftUI

struct RootView: View {
    @State private var model = DemoModel()

    var body: some View {
        TabView {
            ExploreView(model: model)
                .tabItem { Label("Explore", systemImage: "slider.horizontal.3") }
            JamView(model: model)
                .tabItem { Label("Jam", systemImage: "pianokeys") }
        }
        .frame(minWidth: 520, minHeight: 640)
    }
}

#Preview {
    RootView()
}
