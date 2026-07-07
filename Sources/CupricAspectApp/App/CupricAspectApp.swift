import AppKit
import SwiftUI

@main
struct CupricAspectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Single-window app (FR4-050): `Window`, not `WindowGroup`, so ⌘N
        // cannot open a second window with divergent in-memory review state.
        Window("CupricAspect", id: "main") {
            RootShellView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
    }
}

/// Promotes the process to a regular foreground app so `swift run CupricAspect`
/// (a bare SwiftPM binary with no .app bundle) shows a window and takes focus.
/// Harmless once the packaging script wraps the binary in a real bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
