import AppKit
import SwiftUI
import QuartzCore
import VibeKitHost

/// System-composited full-screen background. Strength blends the public material;
/// AppKit does not expose a public arbitrary blur-radius control. No screen capture.
struct SessionScreenBackdrop: NSViewRepresentable {
    var strength: Double
    func makeNSView(context: Context) -> SelectorScreenMaterialView { SelectorScreenMaterialView() }
    func updateNSView(_ view: SelectorScreenMaterialView, context: Context) { view.setStrength(strength) }
}

final class SelectorScreenMaterialView: NSView {
    let effect = NSVisualEffectView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        // Neutral glass, independent of the application's theme. Never add a black scrim.
        effect.appearance = NSAppearance(named: .aqua)
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func setStrength(_ strength: Double) {
        let value = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : SessionOrbit.glass(strength)
        if abs(effect.alphaValue - value) > 0.0001 { effect.alphaValue = value }
    }
    override func layout() { super.layout(); effect.frame = bounds }
}

/// Synthetic backdrop for fixture-only compositor inspection, never part of normal selection UI.
struct OrbitReferenceScene: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            HStack(spacing: 0) {
                ForEach(0..<12) { i in
                    Rectangle().fill(i.isMultiple(of: 2) ? Color.primary.opacity(0.10) : Color.clear)
                }
            }
            VStack(alignment: .leading, spacing: 25) {
                ForEach(0..<12) { i in
                    HStack(spacing: 16) {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 11, design: .monospaced))
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 2)
                        Text("REFERENCE").font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
            }.foregroundStyle(.secondary).padding(40)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
