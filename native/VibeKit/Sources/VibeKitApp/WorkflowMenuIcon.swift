import AppKit
import ImageIO
import VibeKitHost

enum WorkflowMenuIcon {
    struct Mask {
        let width: Int, height: Int
        let alpha: [UInt8]
        let body: [Bool]
        let outerComponents: Int
    }
    private static let cache = NSCache<NSString, NSImage>()
    static func menuHex(_ target: WorkflowTargetID) -> String { target == .deepSeek ? "82C9F5" : WorkflowCatalog.target(target).haloHex }
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
    static func bodyImage(connected: Bool) -> CGImage { raster(primary: .white, secondary: .clear, connected: connected) }
    static func pointScale(_ target: WorkflowTargetID) -> Double { target == .deepSeek ? 1.50 : 1.18 }
    static func make(target: WorkflowTargetID, connected: Bool) -> NSImage {
        let key = "\(target.rawValue)-\(connected)" as NSString
        if let image = cache.object(forKey: key) { return image }
        // Native SF Symbol palette: white primary dial, app-colored secondary perimeter dots.
        let context = CGContext(data: nil, width: 72, height: 64, bitsPerComponent: 8, bytesPerRow: 72 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(bodyImage(connected: connected), in: CGRect(x:0,y:0,width:72,height:64))
        let dots = raster(primary: .clear, secondary: color(target), connected: connected)
        for (bounds, _) in points(connected: connected) {
            let crop = bounds.insetBy(dx:-1,dy:-1).intersection(CGRect(x:0,y:0,width:72,height:64)).integral
            guard let point = dots.cropping(to: crop) else { continue }
            let grown = crop.insetBy(dx: -crop.width * ((pointScale(target) - 1) / 2), dy: -crop.height * ((pointScale(target) - 1) / 2))
            context.draw(point, in: CGRect(x:grown.minX,y:64-grown.maxY,width:grown.width,height:grown.height))
        }
        let cg = context.makeImage()!
        let image = NSImage(cgImage: cg, size: NSSize(width: 18, height: 16))
        image.isTemplate = false
        image.accessibilityDescription = "The Vibekey · " + WorkflowCatalog.target(target).name
        cache.setObject(image, forKey: key)
        return image
    }
}

func runWorkflowMenuIconCheck(path: String) -> Int32 {
    var checks = 0, failures = 0
    func check(_ value: Bool) { checks += 1; if !value { failures += 1 } }
    var results: [[String: Any]] = []
    for connected in [true, false] { for target in WorkflowAppCycle.order {
        let icon = WorkflowMenuIcon.make(target: target, connected: connected)
        let original = WorkflowMenuIcon.mask(connected: connected)
        let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let pixels = [UInt8](cg.dataProvider!.data! as Data)
        let tint = WorkflowMenuIcon.color(target).usingColorSpace(.sRGB)!
        let bodyPixels = [UInt8](WorkflowMenuIcon.bodyImage(connected: connected).dataProvider!.data! as Data)
        var alphaMatches = true, bodyMatches = true, outerMatches = true
        for pixel in original.alpha.indices {
            if bodyPixels[pixel*4+3] > 0 { alphaMatches = alphaMatches && pixels[pixel*4+3] == bodyPixels[pixel*4+3] }
            guard pixels[pixel*4+3] > 240 else { continue }
            let body = bodyPixels[pixel*4+3] > 240
            let alpha = Double(pixels[pixel*4+3])
            let expected = body ? [1.0,1.0,1.0] : [tint.redComponent,tint.greenComponent,tint.blueComponent]
            let matches = (0..<3).allSatisfy { abs(Double(pixels[pixel * 4 + $0]) / alpha - expected[$0]) < 0.015 }
            if body { bodyMatches = bodyMatches && matches } else { outerMatches = outerMatches && matches }
        }
        check(!icon.isTemplate); check(alphaMatches); check(bodyMatches); check(outerMatches)
        check(WorkflowMenuIcon.points(connected: connected).count >= 6)
        results.append(["target": target.rawValue, "connected": connected, "hex": WorkflowMenuIcon.menuHex(target),
                        "originalDialBodyPreserved": alphaMatches, "bodyUnchanged": bodyMatches, "outerComponents": WorkflowMenuIcon.points(connected: connected).count, "pointScale": WorkflowMenuIcon.pointScale(target)])
        if connected {
            let url = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("menu-\(target.rawValue).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
            }
        }
    }}
    let report: [String: Any] = ["checks": checks, "failures": failures, "targets": results, "hardware_or_target_UI_access": false]
    do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path)) }
    catch { return 1 }
    print("Workflow menu icon checks: \(checks), failures: \(failures)")
    return failures == 0 ? 0 : 1
}
