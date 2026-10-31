import AppKit
import SwiftUI
import VibeKitHost

/// Public compositor-backed blur, masked locally. Never blurs unrelated desktop areas.
struct SessionOrbitBackdrop: NSViewRepresentable {
    var strength: Double
    var card = false
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = card ? .popover : .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        // No application-color tint. Match SwiftUI text contrast to the neutral native material.
        if !card { view.maskImage = Self.mask }
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : SessionOrbit.glass(strength)
    }
    private static let mask: NSImage = {
        let size = 512
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        let data = bitmap.bitmapData!
        for y in 0..<size { for x in 0..<size {
            let offset = y * bitmap.bytesPerRow + x * 4
            data[offset] = 0; data[offset + 1] = 0; data[offset + 2] = 0
            data[offset + 3] = UInt8((SessionOrbit.maskAlpha(x: Double(x) / Double(size - 1), y: Double(y) / Double(size - 1)) * 255).rounded())
        } }
        let image = NSImage(size: NSSize(width: size, height: size)); image.addRepresentation(bitmap)
        return image
    }()
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
        }.frame(width: 1200, height: 820)
    }
}
