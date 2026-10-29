import AppKit
import SwiftUI
import VibeKitAudio

/// Isolated native layout preview. VibeVM returns before device, timers and runtime hooks.
@MainActor
func runWorkspacePreview() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.appearance = NSAppearance(named: .aqua)
    let vm = VibeVM()
    vm.scheme = "light"
    let mic = MicMeter()
    let host = NSHostingView(rootView: ContentView().environmentObject(vm).environmentObject(mic))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Open VibeKey · 界面预览"
    window.contentView = host
    window.setContentSize(host.fittingSize)
    window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    if let index = CommandLine.arguments.firstIndex(of: "--preview-image"), index + 1 < CommandLine.arguments.count {
        let path = CommandLine.arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: path)) }
            catch { print("PREVIEW_WRITE_FAILED", error.localizedDescription); exit(1) }
            print("WORKSPACE_PREVIEW_SAVED hardware_started=false target_ui_control=false")
            fflush(stdout); exit(0)
        }
    }
    withExtendedLifetime([vm, mic, host, window] as [Any]) { app.run() }
}

/// A real run-loop test of asynchronous graceful termination, with no device initialization.
@MainActor
func runTerminationSelfTest(outputPath: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppLifecycle()
    app.delegate = delegate
    AppLifecycle.prepareQuit = { completion in
        Task { @MainActor in
            do {
                let row: [String: Any] = ["passed": true, "asynchronous_main_actor_cleanup_reached": true, "hardware_started": false]
                try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: outputPath))
                completion(true)
            } catch { exit(1) }
        }
    }
    Task { @MainActor in AppLifecycle.requestQuit() }
    withExtendedLifetime(delegate) { app.run() }
}
