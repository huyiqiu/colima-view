import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func polygon(_ points: [NSPoint], color: NSColor) {
    let p = NSBezierPath()
    p.move(to: points[0])
    for point in points.dropFirst() { p.line(to: point) }
    p.close(); color.setFill(); p.fill()
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(size) / 1024)
        transform.concat()
        let outline = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 218, yRadius: 218)
        NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.58, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.65, alpha: 1))!.draw(in: outline, angle: -65)
        polygon([NSPoint(x: 512, y: 765), NSPoint(x: 760, y: 628), NSPoint(x: 512, y: 490), NSPoint(x: 264, y: 628)], color: .white)
        polygon([NSPoint(x: 264, y: 600), NSPoint(x: 498, y: 470), NSPoint(x: 498, y: 220), NSPoint(x: 264, y: 350)], color: NSColor.white.withAlphaComponent(0.82))
        polygon([NSPoint(x: 526, y: 470), NSPoint(x: 760, y: 600), NSPoint(x: 760, y: 350), NSPoint(x: 526, y: 220)], color: NSColor.white.withAlphaComponent(0.96))
        polygon([NSPoint(x: 385, y: 695), NSPoint(x: 415, y: 711), NSPoint(x: 655, y: 578), NSPoint(x: 625, y: 561)], color: NSColor(calibratedRed: 0.23, green: 0.45, blue: 0.85, alpha: 0.3))
        let dot = NSBezierPath(ovalIn: NSRect(x: 740, y: 145, width: 136, height: 136))
        NSColor.white.setFill(); dot.fill()
        NSColor(calibratedRed: 0.31, green: 0.84, blue: 0.58, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 752, y: 157, width: 112, height: 112)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let output = directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    }
}
