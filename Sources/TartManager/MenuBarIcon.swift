import AppKit

/// The Outline T selected for Tart Manager's menu-bar control.
///
/// The image is a template, so macOS renders the same approved mark in the
/// appropriate monochrome color against either light or dark wallpapers.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18))
        image.lockFocus()

        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        // Upper isometric plane from the approved Outline T concept.
        path.move(to: NSPoint(x: 2, y: 13.25))
        path.line(to: NSPoint(x: 11, y: 17))
        path.line(to: NSPoint(x: 20, y: 13.25))
        path.line(to: NSPoint(x: 11, y: 9.5))
        path.close()

        // Side walls turn the plane into the T crossbar.
        path.move(to: NSPoint(x: 2, y: 13.25))
        path.line(to: NSPoint(x: 2, y: 9.25))
        path.line(to: NSPoint(x: 8.75, y: 6.4))
        path.move(to: NSPoint(x: 20, y: 13.25))
        path.line(to: NSPoint(x: 20, y: 9.25))
        path.line(to: NSPoint(x: 13.25, y: 6.4))

        // Centered stem, with the shallow point used in the approved mark.
        path.move(to: NSPoint(x: 8.75, y: 10.45))
        path.line(to: NSPoint(x: 8.75, y: 3.4))
        path.line(to: NSPoint(x: 11, y: 1.4))
        path.line(to: NSPoint(x: 13.25, y: 3.4))
        path.line(to: NSPoint(x: 13.25, y: 10.45))

        NSColor.black.setStroke()
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
