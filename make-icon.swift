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

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0.20, alpha: 0.25)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()

let shape = NSBezierPath(roundedRect: NSRect(x: 82, y: 95, width: 860, height: 860), xRadius: 215, yRadius: 215)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.75, green: 0.68, blue: 0.97, alpha: 1),
                          ending: NSColor(calibratedRed: 0.35, green: 0.58, blue: 0.89, alpha: 1))!
gradient.draw(in: shape, angle: -45)

let shine = NSBezierPath(ovalIn: NSRect(x: 215, y: 540, width: 600, height: 290))
NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
shine.fill()

let check = NSBezierPath()
check.move(to: NSPoint(x: 285, y: 510))
check.line(to: NSPoint(x: 445, y: 355))
check.line(to: NSPoint(x: 755, y: 690))
check.lineWidth = 84
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
try png.write(to: URL(fileURLWithPath: output))
