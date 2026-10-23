import AppKit
import SwiftUI

struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = Self(rawValue: 1)
    static let right = Self(rawValue: 2)
    static let bottom = Self(rawValue: 4)
    static let top = Self(rawValue: 8)
}
enum WindowResizeGeometry {
    static func resize(_ frame: NSRect, delta: NSPoint, edges: ResizeEdges, minimum: NSSize, screen: NSRect) -> NSRect {
        var result = frame
        let maxWidth = max(minimum.width, min(900, screen.width - 20))
        let maxHeight = max(minimum.height, min(900, screen.height - 20))
        func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
            min(maximum, max(minimum, value))
        }
        if edges.contains(.left) {
            result.size.width = clamp(frame.width - delta.x, minimum.width, max(minimum.width, min(maxWidth, frame.maxX - screen.minX)))
            result.origin.x = frame.maxX - result.width
        } else if edges.contains(.right) {
            result.size.width = clamp(frame.width + delta.x, minimum.width, max(minimum.width, min(maxWidth, screen.maxX - frame.minX)))
        }
        if edges.contains(.bottom) {
            result.size.height = clamp(frame.height - delta.y, minimum.height, max(minimum.height, min(maxHeight, frame.maxY - screen.minY)))
            result.origin.y = frame.maxY - result.height
        } else if edges.contains(.top) {
            result.size.height = clamp(frame.height + delta.y, minimum.height, max(minimum.height, min(maxHeight, screen.maxY - frame.minY)))
        }
        return result
    }
}

struct WindowResizeEdges: NSViewRepresentable {
    func makeNSView(context: Context) -> EdgeResizeView { EdgeResizeView() }
    func updateNSView(_ view: EdgeResizeView, context: Context) { view.window?.invalidateCursorRects(for: view) }
}
final class EdgeResizeView: NSView {
    private let band: CGFloat = 9
    private let corner: CGFloat = 18
    private var active: ResizeEdges = []
    private var originalFrame = NSRect.zero
    private var originalMouse = NSPoint.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func edges(at point: NSPoint) -> ResizeEdges {
        guard bounds.contains(point) else { return [] }
        var edges: ResizeEdges = []
        let nearLeft = point.x < corner, nearRight = point.x > bounds.maxX - corner
        let nearBottom = point.y < corner, nearTop = point.y > bounds.maxY - corner
        if point.x < band || (nearLeft && (nearTop || nearBottom)) { edges.insert(.left) }
        if point.x > bounds.maxX - band || (nearRight && (nearTop || nearBottom)) { edges.insert(.right) }
        if point.y < band || (nearBottom && (nearLeft || nearRight)) { edges.insert(.bottom) }
        if point.y > bounds.maxY - band || (nearTop && (nearLeft || nearRight)) { edges.insert(.top) }
        return edges
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return edges(at: local).isEmpty ? nil : self
    }
    private static func diagonal(_ name: String) -> NSCursor {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return .crosshair }
        image.size = NSSize(width: 18, height: 18)
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
    }
    private static let downDiagonal = diagonal("arrow.up.left.and.arrow.down.right")
    private static let upDiagonal = diagonal("arrow.up.right.and.arrow.down.left")
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: 0, y: 0, width: band, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.maxX - band, y: 0, width: band, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: band), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: bounds.maxY - band, width: bounds.width, height: band), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: bounds.maxY - corner, width: corner, height: corner), cursor: Self.downDiagonal)
        addCursorRect(NSRect(x: bounds.maxX - corner, y: 0, width: corner, height: corner), cursor: Self.downDiagonal)
        addCursorRect(NSRect(x: 0, y: 0, width: corner, height: corner), cursor: Self.upDiagonal)
        addCursorRect(NSRect(x: bounds.maxX - corner, y: bounds.maxY - corner, width: corner, height: corner), cursor: Self.upDiagonal)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        active = edges(at: convert(event.locationInWindow, from: nil))
        originalFrame = window.frame
        originalMouse = NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, !active.isEmpty else { return }
        let current = NSEvent.mouseLocation
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? originalFrame
        let next = WindowResizeGeometry.resize(originalFrame,
            delta: NSPoint(x: current.x - originalMouse.x, y: current.y - originalMouse.y),
            edges: active, minimum: window.minSize, screen: screen)
        window.setFrame(next, display: true)
        window.invalidateCursorRects(for: self)
    }
    override func mouseUp(with event: NSEvent) { active = [] }
}

// Explicit AppKit drag regions avoid SwiftUI buttons swallowing window-background drags.
struct WindowDragSurface: NSViewRepresentable {
    var click: (() -> Void)? = nil
    func makeNSView(context: Context) -> WindowDragView { let view = WindowDragView(); view.click = click; return view }
    func updateNSView(_ view: WindowDragView, context: Context) { view.click = click }
}
final class WindowDragView: NSView {
    var click: (() -> Void)?
    private var origin = NSPoint.zero
    private var mouse = NSPoint.zero
    private var dragged = false
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        origin = window?.frame.origin ?? .zero; mouse = NSEvent.mouseLocation; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - mouse.x, dy = current.y - mouse.y
        guard dragged || hypot(dx, dy) > 3 else { return }
        dragged = true; NSCursor.closedHand.set()
        window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        if !dragged { click?() }
        else if let window, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? window.screen {
            window.setFrame(WindowDockGeometry.clamped(window.frame, to: screen.visibleFrame), display: true)
        }
        dragged = false
    }
}
enum WindowDockGeometry {
    static func clamped(_ frame: NSRect, to screen: NSRect) -> NSRect {
        NSRect(x: min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width)),
               y: min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY - frame.height)),
               width: frame.width, height: frame.height)
    }
    static func collapsed(from frame: NSRect, screen: NSRect, size: CGFloat = 52) -> NSPoint {
        NSPoint(x: frame.midX < screen.midX ? screen.minX + 12 : screen.maxX - size - 12,
                y: frame.midY < screen.midY ? screen.minY + 12 : screen.maxY - size - 12)
    }
    static func expanded(from orb: NSRect, size: NSSize, screen: NSRect) -> NSRect {
        clamped(NSRect(x: orb.midX < screen.midX ? orb.minX : orb.maxX - size.width,
                       y: orb.midY < screen.midY ? orb.minY : orb.maxY - size.height,
                       width: size.width, height: size.height), to: screen)
    }
}
