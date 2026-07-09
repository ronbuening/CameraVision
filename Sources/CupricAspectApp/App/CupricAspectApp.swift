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
@MainActor
enum TerminationFlush {
    private static var actions: [String: () -> Void] = [:]

    static func register(id: String, _ action: @escaping () -> Void) {
        actions[id] = action
    }

    static func runAll() {
        for action in actions.values {
            action()
        }
    }

    static func _resetForTesting() {
        actions.removeAll()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // M8 hygiene: stale per-run artifact directories are scratch, not
        // user data — prune off the main thread at launch.
        let stateDirectory = ReviewModel.defaultStateDirectory
        Task.detached(priority: .utility) {
            StateHousekeeping.pruneArtifacts(in: stateDirectory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        TerminationFlush.runAll()
        return .terminateNow
    }
}
