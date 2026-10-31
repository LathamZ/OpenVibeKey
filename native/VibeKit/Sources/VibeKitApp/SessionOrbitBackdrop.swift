import AppKit
import SwiftUI
import VibeKitHost

/// Public compositor-backed blur, masked locally. Never blurs unrelated desktop areas.
struct SessionOrbitBackdrop: NSViewRepresentable {
    var strength: Double
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0 : SessionOrbit.glass(strength)
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
