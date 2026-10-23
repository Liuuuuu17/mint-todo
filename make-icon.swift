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

// White tile and a simple black checkmark.
context.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.16)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
let tile = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 196, yRadius: 196)
NSColor.white.setFill()
tile.fill()
context.restoreGraphicsState()
NSColor(white: 1, alpha: 0.8).setStroke()
tile.lineWidth = 3
tile.stroke()

let check = NSBezierPath()
check.move(to: NSPoint(x: 300, y: 510))
check.line(to: NSPoint(x: 455, y: 365))
check.line(to: NSPoint(x: 725, y: 665))
check.lineWidth = 76
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.black.setStroke()
check.stroke()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
try png.write(to: URL(fileURLWithPath: output))
