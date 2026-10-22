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

context.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.23, alpha: 0.18)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
let tile = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(calibratedRed: 0.77, green: 0.96, blue: 0.87, alpha: 1),
           ending: NSColor(calibratedRed: 0.48, green: 0.83, blue: 0.69, alpha: 1))!.draw(in: tile, angle: -90)
context.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.55).setStroke()
tile.lineWidth = 3
tile.stroke()

let ink = NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.28, alpha: 1)
let check = NSBezierPath()
check.move(to: NSPoint(x: 300, y: 500))
check.line(to: NSPoint(x: 452, y: 354))
check.line(to: NSPoint(x: 674, y: 620))
check.lineWidth = 74
check.lineCapStyle = .round
check.lineJoinStyle = .round
ink.setStroke()
check.stroke()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
try png.write(to: URL(fileURLWithPath: output))
