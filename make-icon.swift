import AppKit

let output = CommandLine.arguments[1]
let size = 1024
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot draw icon") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// Monochrome editorial mark: warm paper, graphite ink, no accent colour.
context.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.16)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
let tile = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(white: 0.98, alpha: 1),
           ending: NSColor(white: 0.90, alpha: 1))!.draw(in: tile, angle: -90)
context.restoreGraphicsState()
NSColor(white: 1, alpha: 0.8).setStroke()
tile.lineWidth = 3
tile.stroke()

let ink = NSColor(white: 0.13, alpha: 1)
let font = NSFont(name: "Baskerville-Italic", size: 670) ?? NSFont.systemFont(ofSize: 560, weight: .light)
let mark = NSAttributedString(string: "m", attributes: [.font: font, .foregroundColor: ink])
let bounds = mark.size()
mark.draw(at: NSPoint(x: (1024 - bounds.width) / 2 - 18, y: 245))
// A restrained full stop doubles as the app's floating dot when collapsed.
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: 715, y: 322, width: 45, height: 45)).fill()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
try png.write(to: URL(fileURLWithPath: output))
