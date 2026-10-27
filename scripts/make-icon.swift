import AppKit
import Foundation

let root = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: root).appendingPathComponent("Aside.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let shape = NSBezierPath(roundedRect: NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.90, height: p * 0.90), xRadius: p * 0.22, yRadius: p * 0.22)
        NSColor(calibratedRed: 0.29, green: 0.39, blue: 0.32, alpha: 1).setFill()
        shape.fill()
        let font = NSFont(name: "Georgia-Italic", size: p * 0.85) ?? NSFont.systemFont(ofSize: p * 0.85, weight: .medium)
        ("a" as NSString).draw(at: NSPoint(x: p * 0.23, y: p * 0.04), withAttributes: [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 1)])
        NSColor(calibratedRed: 0.81, green: 0.87, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: p * 0.68, y: p * 0.23, width: p * 0.095, height: p * 0.095)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
