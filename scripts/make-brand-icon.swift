#!/usr/bin/env swift
import AppKit

// Original vector artwork for the Vibekey: a tactile V inside a continuous orbit.
// No fonts, external artwork or upstream icon assets. Re-render at every icon size.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets/the-vibekey")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = output.appendingPathComponent("TheVibekey.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
}
func render(_ pixels: Int, to file: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let frame = NSRect(x: 64, y: 64, width: 896, height: 896)
    let tile = NSBezierPath(roundedRect: frame, xRadius: 204, yRadius: 204)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -13), blur: 24, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    color(0x18373B).setFill(); tile.fill()
    context.restoreGState()
    NSGradient(starting: color(0x355B60), ending: color(0x102C32))!.draw(in: tile, angle: -75)
    NSColor.white.withAlphaComponent(0.16).setStroke(); tile.lineWidth = 3; tile.stroke()
    // Elliptical orbit remains recognizable at menu-icon sizes.
    let orbit = NSBezierPath(ovalIn: NSRect(x: 186, y: 310, width: 652, height: 362))
    color(0xA0CDC2).withAlphaComponent(0.48).setStroke(); orbit.lineWidth = 19; orbit.stroke()
    // Broad rounded V: both a directional gesture and the product initial.
    let v = NSBezierPath()
    v.move(to: NSPoint(x: 350, y: 638)); v.line(to: NSPoint(x: 512, y: 359)); v.line(to: NSPoint(x: 674, y: 638))
    v.lineWidth = 74; v.lineCapStyle = .round; v.lineJoinStyle = .round
    context.saveGState(); context.setShadow(offset: CGSize(width: 0, height: -7), blur: 14, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    color(0xE9F3EC).setStroke(); v.stroke(); context.restoreGState()
    for (x, y, radius, hex) in [(210.0, 555.0, 27.0, UInt32(0xA8CDC2)), (758.0, 605.0, 20.0, UInt32(0xD3DEC3)), (677.0, 335.0, 16.0, UInt32(0x839DE1))] {
        color(hex).setFill(); NSBezierPath(ovalIn: NSRect(x: x-radius, y: y-radius, width: 2*radius, height: 2*radius)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: file)
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        try render(points * scale, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
try render(1024, to: output.appendingPathComponent("TheVibekey.png"))
print("Original orbit icon rendered to \(output.path)")
