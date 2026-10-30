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

// Distinct, readable input-mode indicators at native menu-bar sizes.
for (name, glyph) in [("AsideChinese", "中"), ("AsideEnglish", "A")] {
    let folder = URL(fileURLWithPath: root).appendingPathComponent(name + ".iconset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let p = CGFloat(size * scale)
            let image = NSImage(size: NSSize(width: p, height: p))
            image.lockFocus()
            NSColor(calibratedRed: 0.29, green: 0.39, blue: 0.32, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92), xRadius: p * 0.18, yRadius: p * 0.18).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: p * 0.72, weight: .semibold), .foregroundColor: NSColor.white]
            let text = glyph as NSString
            let measured = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (p - measured.width) / 2, y: (p - measured.height) / 2), withAttributes: attributes)
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render mode icon") }
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
}
