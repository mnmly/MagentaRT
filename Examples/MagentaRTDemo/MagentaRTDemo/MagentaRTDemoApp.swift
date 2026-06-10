//
//  MagentaRTDemoApp.swift
//  MagentaRTDemo
//

import SwiftUI
import AppKit

@main
struct MagentaRTDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Cleanly stop streaming before the process exits. Without this, Quit tears
/// down MLX's Metal objects while the inference thread still has GPU work in
/// flight (Metal API Validation asserts in Debug). `applicationShouldTerminate`
/// defers termination until `MagentaPlayer.stop()` has joined the inference
/// thread and the GPU is idle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let model = DemoModel.current, model.isStreaming else { return .terminateNow }
            Task { @MainActor in
                await model.stop()
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
