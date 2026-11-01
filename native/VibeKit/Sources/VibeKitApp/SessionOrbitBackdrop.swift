import AppKit
import SwiftUI
import QuartzCore
import VibeKitHost

/// Explicitly sized neutral backdrop; alpha is a separate, centered layer, never maskImage.
struct SessionOrbitBackdrop: NSViewRepresentable {
    var strength: Double
    var card = false
    func makeNSView(context: Context) -> OrbitMaterialView {
        OrbitMaterialView(card: card)
    }
    func updateNSView(_ view: OrbitMaterialView, context: Context) {
        // White selector text does not require a dark backdrop. Keep neutral light glass
        // independently of the desktop/app theme instead of adding a dark material wash.
        let appearance: NSAppearance.Name = .aqua
        if view.effect.appearance?.name != appearance { view.effect.appearance = NSAppearance(named: appearance) }
        let alpha = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : SessionOrbit.glass(strength)
        if abs(view.alphaValue - alpha) > 0.0001 { view.alphaValue = alpha }
    }
}

final class OrbitMaterialView: NSView {
    let effect = NSVisualEffectView()
    private let feather = CALayer()
    private let card: Bool
    init(card: Bool) {
        self.card = card
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        effect.material = card ? .popover : .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = nil
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
        if !card {
            feather.contents = Self.featherImage
            feather.contentsGravity = .resize
            layer?.mask = feather
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effect.frame = bounds
        if !card { feather.frame = bounds }
        CATransaction.commit()
    }
    private static let featherImage: CGImage = {
        let size = 512
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size { for x in 0..<size {
            bytes[(y * size + x) * 4 + 3] = UInt8((SessionOrbit.maskAlpha(x: Double(x) / Double(size - 1), y: Double(y) / Double(size - 1)) * 255).rounded())
        } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
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
