import AppKit
import SwiftUI
import ImageIO
import VibeKitHost

/// MenuBarExtra may extract a single Image from its label instead of rendering
/// a general SwiftUI stack. Supply one complete image, with every decoration.
struct NativeWorkflowMenuIcon: View {
    let target: WorkflowTargetID
    let connected: Bool
    var body: some View {
        Image(nsImage: WorkflowMenuIcon.adaptiveImage(target: target, connected: connected))
            .renderingMode(.original).frame(width: 18, height: 18)
    }
}

/// Drawing handlers may be called off the main thread. Probe-only audit is locked.
final class MenuImageDrawAudit: @unchecked Sendable {
    static let shared = MenuImageDrawAudit()
    private let lock = NSLock()
    private var values: [[String: Any]] = []
    func record(appearance: NSAppearance, target: WorkflowTargetID, connected: Bool) {
        guard CommandLine.arguments.contains("--menu-surface-preview") else { return }
        lock.lock(); defer { lock.unlock() }
        values.append(["appearance": appearance.name.rawValue, "target": target.rawValue,
                       "connected": connected, "complete_composite": true,
                       "pointer_filled": WorkflowMenuIcon.fillsPointer(target: target, appearance: appearance)])
    }
    func snapshot() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return values }
}

func menuSurfacePreviewTarget() -> WorkflowTargetID {
    if let i = CommandLine.arguments.firstIndex(of: "--menu-preview-target"), i + 1 < CommandLine.arguments.count,
       let target = WorkflowTargetID(rawValue: CommandLine.arguments[i + 1]) { return target }
    return .deepSeek
}

/// Isolated real MenuBarExtra run; audit the actual complete image drawing handler.
@MainActor
func beginMenuSurfacePreview(path: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        let draws = MenuImageDrawAudit.shared.snapshot()
        let surfaces = Set(draws.compactMap { $0["appearance"] as? String }).sorted()
        let light = surfaces.contains { $0.contains("Light") || $0 == NSAppearance.Name.aqua.rawValue }
        let dark = surfaces.contains { $0.contains("Dark") }
        let result: [String: Any] = ["passed": light && dark, "surfaces": surfaces, "draws": draws,
            "both_surface_variants_drawn": light && dark,
            "foreground_strategy": "one adaptive image; Codex native hollow pointer on every surface",
            "target": menuSurfacePreviewTarget().rawValue,
            "codex_pointer_never_filled": !draws.isEmpty && draws.filter { $0["target"] as? String == "codex" }.allSatisfy { $0["pointer_filled"] as? Bool == false },
            "app_appearance": NSApp.effectiveAppearance.name.rawValue,
            "system_setting_changed": false, "hardware_started": false,
            "final_visible_variant_verified": false]
        do { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path)) }
        catch { exit(1) }
        exit(light && dark ? 0 : 1)
    }
}

enum WorkflowMenuIcon {
    struct Mask {
        let width: Int, height: Int
        let alpha: [UInt8]
        let body: [Bool]
        let outerComponents: Int
    }
    private static let cache = NSCache<NSString, NSImage>()
    static func menuHex(_ target: WorkflowTargetID) -> String {
        switch target {
        case .deepSeek: return "82C9F5"
        case .weChat: return "3DCE82"
        default: return WorkflowCatalog.target(target).haloHex
        }
    }
    static func color(_ target: WorkflowTargetID) -> NSColor {
        let hex = menuHex(target)
        let value = UInt32(hex, radix: 16) ?? 0xFFFFFF
        return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                       green: Double((value >> 8) & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }
    private static let connectedMask = originalMask(connected: true)
    private static let disconnectedMask = originalMask(connected: false)
    static func mask(connected: Bool) -> Mask { connected ? connectedMask : disconnectedMask }
    private static func raster(primary: NSColor = .white, secondary: NSColor = .white, connected: Bool) -> CGImage {
        let glyph = NSImage(systemSymbolName: connected ? "dial.medium.fill" : "dial.medium", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [primary, secondary]))!
        let context = CGContext(data: nil, width: 72, height: 64, bitsPerComponent: 8, bytesPerRow: 72 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        glyph.draw(in: NSRect(x: 0, y: 0, width: 72, height: 64))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
    private static func originalMask(connected: Bool) -> Mask {
        let original = raster(connected: connected), width = 72, height = 64
        let rgba = [UInt8](original.dataProvider!.data! as Data)
        let alpha = (0..<(width * height)).map { rgba[$0 * 4 + 3] }
        var visited = Set<Int>(), components: [([Int], CGRect)] = []
        for start in alpha.indices where alpha[start] >= 24 && !visited.contains(start) {
            var stack = [start], members: [Int] = [], minX = width, minY = height, maxX = 0, maxY = 0
            visited.insert(start)
            while let pixel = stack.popLast() {
                members.append(pixel)
                let x = pixel % width, y = pixel / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    if alpha[next] >= 24, visited.insert(next).inserted { stack.append(next) }
                }
            }
            components.append((members, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)))
        }
        let bodyBounds = components.max(by: { $0.0.count < $1.0.count })!.1
        var body = [Bool](repeating: false, count: width * height), outerCount = 0
        for (members, bounds) in components {
            let dx = (bounds.midX - bodyBounds.midX) / (bodyBounds.width / 2)
            let dy = (bounds.midY - bodyBounds.midY) / (bodyBounds.height / 2)
            if dx * dx + dy * dy < 1.05 {
                for pixel in members { body[pixel] = true }
            } else if members.count >= 4 { outerCount += 1 }
        }
        return Mask(width: width, height: height, alpha: alpha, body: body, outerComponents: outerCount)
    }
    static func points(connected: Bool) -> [(CGRect, Int)] {
        let image = raster(primary: .clear, secondary: .white, connected: connected)
        let rgba = [UInt8](image.dataProvider!.data! as Data), width = 72, height = 64
        var seen = Set<Int>(), result: [(CGRect, Int)] = []
        for start in 0..<(width * height) where rgba[start * 4 + 3] > 8 && !seen.contains(start) {
            var stack = [start], count = 0, x0 = width, x1 = 0, y0 = height, y1 = 0
            seen.insert(start)
            while let pixel = stack.popLast() {
                count += 1; let x = pixel % width, y = pixel / width
                x0 = min(x0,x); x1 = max(x1,x); y0 = min(y0,y); y1 = max(y1,y)
                for (dx,dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nx=x+dx, ny=y+dy
                    if nx >= 0, nx < width, ny >= 0, ny < height {
                        let next=ny*width+nx
                        if rgba[next*4+3] > 8, seen.insert(next).inserted { stack.append(next) }
                    }
                }
            }
            if count >= 4 { result.append((CGRect(x:x0,y:y0,width:x1-x0+1,height:y1-y0+1), count)) }
        }
        return result
    }
    private static var templates: [Bool: NSImage] = [:]
    static func bodyTemplate(connected: Bool) -> NSImage {
        if let image = templates[connected] { return image }
        let image = NSImage(cgImage: raster(primary: .white, secondary: .clear, connected: connected), size: NSSize(width: 18, height: 16))
        image.isTemplate = true
        templates[connected] = image
        return image
    }
    static func dotImage(target: WorkflowTargetID, connected: Bool) -> NSImage {
        let key = "dots-\(target.rawValue)-\(connected)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let context = CGContext(data: nil, width: 72, height: 64, bitsPerComponent: 8, bytesPerRow: 72 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        drawDots(target: target, connected: connected, context: context)
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 18, height: 16))
        image.isTemplate = false
        cache.setObject(image, forKey: key)
        return image
    }
    private static func drawDots(target: WorkflowTargetID, connected: Bool, context: CGContext) {
        let dots = raster(primary: .clear, secondary: color(target), connected: connected)
        for (bounds, _) in points(connected: connected) {
            let crop = bounds.insetBy(dx: -1, dy: -1).intersection(CGRect(x: 0, y: 0, width: 72, height: 64)).integral
            guard let point = dots.cropping(to: crop) else { continue }
            let grown = crop.insetBy(dx: -crop.width * ((pointScale(target) - 1) / 2), dy: -crop.height * ((pointScale(target) - 1) / 2))
            context.draw(point, in: CGRect(x: grown.minX, y: 64 - grown.maxY, width: grown.width, height: grown.height))
        }
    }
    static func adaptiveImage(target: WorkflowTargetID, connected: Bool) -> NSImage {
        let key = "adaptive-\(target.rawValue)-\(connected)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { rect in
            let appearance = NSAppearance.currentDrawing()
            make(target: target, connected: connected, appearance: appearance).draw(in: rect)
            MenuImageDrawAudit.shared.record(appearance: appearance, target: target, connected: connected)
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        image.accessibilityDescription = "The Vibekey · " + WorkflowCatalog.target(target).name
        cache.setObject(image, forKey: key)
        return image
    }
    /// Fill only the original filled symbol's narrow internal gap. Deriving it
    /// from the native alpha preserves the pointer shape instead of drawing a new bar.
    private static let pointerAlpha: [UInt8] = {
        let source = raster(primary: .white, secondary: .clear, connected: true)
        let rgba = [UInt8](source.dataProvider!.data! as Data)
        var alpha = [UInt8](repeating: 0, count: 72 * 64)
        for y in 0..<64 {
            let solid = (0..<72).filter { rgba[(y * 72 + $0) * 4 + 3] >= 220 }
            guard let left = solid.first, let right = solid.last, right - left >= 8 else { continue }
            let center = Double(left + right) / 2
            let halfGap = Double(right - left) * 0.20
            for x in (left + 1)..<right where abs(Double(x) - center) <= halfGap {
                let pixel = y * 72 + x
                alpha[pixel] = 255 - rgba[pixel * 4 + 3]
            }
        }
        return alpha
    }()
    static var pointerPixelCount: Int { pointerAlpha.filter { $0 > 180 }.count }
    static func pointerImage(target: WorkflowTargetID) -> CGImage {
        let tint = color(target).usingColorSpace(.sRGB)!
        var rgba = [UInt8](repeating: 0, count: 72 * 64 * 4)
        for i in pointerAlpha.indices {
            let a = Double(pointerAlpha[i])
            rgba[i * 4] = UInt8((tint.redComponent * a).rounded())
            rgba[i * 4 + 1] = UInt8((tint.greenComponent * a).rounded())
            rgba[i * 4 + 2] = UInt8((tint.blueComponent * a).rounded())
            rgba[i * 4 + 3] = pointerAlpha[i]
        }
        return CGImage(width: 72, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 72 * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
    static func bodyColor(appearance: NSAppearance) -> NSColor {
        var resolved = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.sRGB)!
        }
        return resolved
    }
    static func bodyColor(darkAppearance: Bool) -> NSColor {
        bodyColor(appearance: NSAppearance(named: darkAppearance ? .darkAqua : .aqua)!)
    }
    static func bodyImage(connected: Bool, darkAppearance: Bool = false) -> CGImage {
        raster(primary: bodyColor(darkAppearance: darkAppearance), secondary: .clear, connected: connected)
    }
    static func pointScale(_ target: WorkflowTargetID) -> Double { 1.50 }
    static func make(target: WorkflowTargetID, connected: Bool, darkAppearance: Bool = false) -> NSImage {
        make(target: target, connected: connected, appearance: NSAppearance(named: darkAppearance ? .darkAqua : .aqua)!)
    }
    /// Codex keeps the native hollow pointer in every actual drawing appearance.
    /// A white body is not evidence of a light menu surface; never fill its gap.
    static func fillsPointer(target: WorkflowTargetID, appearance: NSAppearance) -> Bool {
        target != .codex
    }
    static func make(target: WorkflowTargetID, connected: Bool, appearance: NSAppearance) -> NSImage {
        let foreground = bodyColor(appearance: appearance)
        let key = "\(target.rawValue)-\(connected)-\(appearance.name.rawValue)-\(foreground.redComponent)-\(foreground.greenComponent)-\(foreground.blueComponent)-\(foreground.alphaComponent)" as NSString
        if let image = cache.object(forKey: key) { return image }
        // Only the dial follows appearance; the perimeter keeps the target App's color.
        let context = CGContext(data: nil, width: 72, height: 64, bitsPerComponent: 8, bytesPerRow: 72 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(raster(primary: foreground, secondary: .clear, connected: connected), in: CGRect(x:0,y:0,width:72,height:64))
        if fillsPointer(target: target, appearance: appearance) {
            context.draw(pointerImage(target: target), in: CGRect(x: 0, y: 0, width: 72, height: 64))
        }
        drawDots(target: target, connected: connected, context: context)
        let cg = context.makeImage()!
        let image = NSImage(cgImage: cg, size: NSSize(width: 18, height: 16))
        image.isTemplate = false
        image.accessibilityDescription = "The Vibekey · " + WorkflowCatalog.target(target).name
        cache.setObject(image, forKey: key)
        return image
    }
}

@MainActor
func runWorkflowMenuIconCheck(path: String) -> Int32 {
    var checks = 0, failures = 0
    func check(_ value: Bool) { checks += 1; if !value { failures += 1 } }
    check(WorkflowMenuIcon.pointerPixelCount >= 5)
    var results: [[String: Any]] = []
    for darkAppearance in [false, true] { for connected in [true, false] { for target in WorkflowAppCycle.order {
        let icon = WorkflowMenuIcon.make(target: target, connected: connected, darkAppearance: darkAppearance)
        let original = WorkflowMenuIcon.mask(connected: connected)
        let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let pixels = [UInt8](cg.dataProvider!.data! as Data)
        let tint = WorkflowMenuIcon.color(target).usingColorSpace(.sRGB)!
        let bodyPixels = [UInt8](WorkflowMenuIcon.bodyImage(connected: connected, darkAppearance: darkAppearance).dataProvider!.data! as Data)
        let dotPixels = [UInt8](WorkflowMenuIcon.dotImage(target: target, connected: connected).cgImage(forProposedRect: nil, context: nil, hints: nil)!.dataProvider!.data! as Data)
        // Inspect the original notch interior: the light Codex variant must
        // retain its original alpha, while the other variants keep their tint.
        let pointerPixels = [UInt8](WorkflowMenuIcon.pointerImage(target: target).dataProvider!.data! as Data)
        let notch = original.alpha.indices.filter { bodyPixels[$0*4+3] < 8 && dotPixels[$0*4+3] < 8 && pointerPixels[$0*4+3] > 220 }
        // The disconnected SF Symbol is an outline with no filled-body notch.
        // Existing body/dot and full-image checks cover that variant.
        if connected {
            check(!notch.isEmpty)
            if target == .codex {
                check(notch.allSatisfy { pixels[$0*4+3] == bodyPixels[$0*4+3] })
            } else {
                check(notch.allSatisfy { pixels[$0*4+3] > 220 })
            }
        }
        var alphaMatches = true, bodyMatches = true, outerMatches = true, bodySamples = 0
        for pixel in original.alpha.indices {
            if bodyPixels[pixel*4+3] > 0 { alphaMatches = alphaMatches && pixels[pixel*4+3] >= bodyPixels[pixel*4+3] }
            guard pixels[pixel*4+3] > 180 else { continue }
            let body = bodyPixels[pixel*4+3] > 180
            // Classify perimeter dots by their own alpha mask.
            guard body || dotPixels[pixel*4+3] > 180 else { continue }
            let alpha = Double(pixels[pixel*4+3])
            let foreground = WorkflowMenuIcon.bodyColor(darkAppearance: darkAppearance)
            let expected = body ? [foreground.redComponent,foreground.greenComponent,foreground.blueComponent] : [tint.redComponent,tint.greenComponent,tint.blueComponent]
            let tintValues = [tint.redComponent, tint.greenComponent, tint.blueComponent]
            let matches = (0..<3).allSatisfy {
                let channel = Double(pixels[pixel * 4 + $0]) / alpha
                if body { return channel >= min(expected[$0], tintValues[$0]) - 0.015 && channel <= max(expected[$0], tintValues[$0]) + 0.015 }
                return abs(channel - expected[$0]) < 0.015
            }
            if body { bodySamples += 1; bodyMatches = bodyMatches && matches } else { outerMatches = outerMatches && matches }
        }
        check(WorkflowMenuIcon.pointScale(target) == WorkflowMenuIcon.pointScale(.deepSeek));
        check(!icon.isTemplate); check(alphaMatches); check(bodyMatches); check(outerMatches)
        check(WorkflowMenuIcon.points(connected: connected).count >= 6)
        check(bodySamples > 100)
        let cached = WorkflowMenuIcon.make(target: target, connected: connected, darkAppearance: darkAppearance)
        let opposite = WorkflowMenuIcon.make(target: target, connected: connected, darkAppearance: !darkAppearance)
        check(cached === icon); check(opposite !== icon)
        results.append(["target": target.rawValue, "connected": connected, "darkAppearance": darkAppearance, "hex": WorkflowMenuIcon.menuHex(target),
                        "originalDialBodyPreserved": alphaMatches, "bodyForegroundAndPointerValid": bodyMatches, "outerComponents": WorkflowMenuIcon.points(connected: connected).count, "pointScale": WorkflowMenuIcon.pointScale(target),
                        "pointerFillMode": target == .codex ? "native-transparent-gap" : "app-color",
                        "notchSamples": notch.count])
        if connected {
            let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("menu-\(target.rawValue)-\(darkAppearance ? "dark" : "light").png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
            }
        }
    }}}
    // Render the same complete image under a local drawing appearance while
    // the global App theme is opposite. The draw handler must not use NSApp.
    let application = NSApplication.shared
    let savedAppearance = application.appearance
    var surfaceResults: [[String: Any]] = []
    for dark in [false, true] { for target in WorkflowAppCycle.order {
        application.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let adaptive = WorkflowMenuIcon.adaptiveImage(target: target, connected: true)
        var drawn: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            let bitmap = CGContext(data: nil, width: 72, height: 64, bitsPerComponent: 8, bytesPerRow: 72 * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
            adaptive.draw(in: NSRect(x: 0, y: 0, width: 72, height: 64))
            NSGraphicsContext.restoreGraphicsState()
            drawn = bitmap.makeImage()
        }
        guard let cg = drawn else { check(false); continue }
        let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let body = WorkflowMenuIcon.bodyTemplate(connected: true).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bodyData = [UInt8](body.dataProvider!.data! as Data)
        var samples = 0, match = true
        // The complete image is 18x16 at four-times scale.
        for y in 0..<64 { for x in 0..<72 where bodyData[(y * 72 + x) * 4 + 3] > 220 {
            let pixel = (y * cg.width + x) * 4
            guard bytes[pixel + 3] > 150 else { continue }
            let brightness = Double(bytes[pixel]) / Double(bytes[pixel + 3])
            match = match && (dark ? brightness > 0.7 : brightness < 0.3); samples += 1
        }}
        check(samples > 100); check(match)
        check(!adaptive.isTemplate)
        check(adaptive.cacheMode == .never)
        check(adaptive === WorkflowMenuIcon.adaptiveImage(target: target, connected: true))
        let expected = WorkflowMenuIcon.make(target: target, connected: true, appearance: appearance).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        // Normalize both images through the same premultiplied sRGB context.
        // NSImage can expose a different byte layout from its source CGImage.
        let expectedContext = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        expectedContext.draw(expected, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let expectedData = Array(UnsafeBufferPointer(start: expectedContext.data!.assumingMemoryBound(to: UInt8.self), count: cg.width * cg.height * 4))
        let actualData = Array(UnsafeBufferPointer(start: bytes, count: cg.width * cg.height * 4))
        check(zip(actualData, expectedData).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
        // No glow may remain outside the dial, enlarged dots and pointer masks.
        let bodyMask = WorkflowMenuIcon.mask(connected: true)
        let dotMask = WorkflowMenuIcon.dotImage(target: target, connected: true).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let dotData = [UInt8](dotMask.dataProvider!.data! as Data)
        let pointerData = [UInt8](WorkflowMenuIcon.pointerImage(target: target).dataProvider!.data! as Data)
        let haloSamples = (0..<(72 * 64)).filter {
            bodyMask.alpha[$0] < 8 && dotData[$0 * 4 + 3] < 8 && pointerData[$0 * 4 + 3] < 8 && actualData[$0 * 4 + 3] >= 24
        }.count
        check(haloSamples == 0)
        surfaceResults.append(["darkSurface": dark, "target": target.rawValue, "appOpposite": true,
                               "bodyPixelSamples": samples, "systemForegroundMatches": match])
        if target == .deepSeek {
            let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("label-\(dark ? "dark" : "light").png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
            }
        }
    }}
    for name in [NSAppearance.Name.aqua, .vibrantLight, .accessibilityHighContrastAqua,
                 .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua] {
        guard let appearance = NSAppearance(named: name) else { check(false); continue }
        check(!WorkflowMenuIcon.fillsPointer(target: .codex, appearance: appearance))
        for target in WorkflowAppCycle.order where target != .codex {
            check(WorkflowMenuIcon.fillsPointer(target: target, appearance: appearance))
        }
    }
    application.appearance = savedAppearance
    let report: [String: Any] = ["checks": checks, "failures": failures, "targets": results,
                               "native_surface_appearance_checks": surfaceResults,
                               "foreground_source": "complete adaptive image resolves current drawing appearance; Codex native transparent gap in every drawing appearance; app-colored pointer for other targets; perimeter dots unchanged, no glow",
                               "system_setting_changed": false, "hardware_or_target_UI_access": false]
    do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path)) }
    catch { return 1 }
    print("Workflow menu icon checks: \(checks), failures: \(failures)")
    return failures == 0 ? 0 : 1
}
