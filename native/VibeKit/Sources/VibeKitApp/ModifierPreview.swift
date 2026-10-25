import AppKit
import SwiftUI

/// Uses the production editor with in-memory state, without opening the device or preferences.
private struct ModifierPreview: View {
    @State private var state = ButtonState(id: "btn1", title: "按钮 1", mods: ["ROpt"], mainKey: "A", current: "右⌥+A")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open VibeKey · 左右修饰键").font(.headline)
            ShortcutEditor(b: $state,
                           onApply: { state.current = state.tokens.joined(separator: "+") },
                           onClear: { state.mods = []; state.mainKey = nil; state.current = "未设置" })
        }
        .padding(20)
        .frame(width: AppLanguage.shared.resolved == .english ? 470 : 420)
    }
}

func runModifierPreview() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Open VibeKey Modifier Preview"
    window.contentView = NSHostingView(rootView: ModifierPreview())
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
