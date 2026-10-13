import AppKit

/// The Tart Manager pastry mark for the menu-bar control.
///
/// The filled fluted silhouette leaves the lower-right M as an alpha cutout.
/// The image is a template, so macOS supplies its monochrome color against
/// either light or dark wallpapers.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.windingRule = .evenOdd

            // A shallow five-flute rim and projecting lip sit above the
            // tapered pastry body. Drawing handlers preserve the path at the
            // backing scale instead of caching a single lockFocus bitmap.
            path.move(to: NSPoint(x: 0.8, y: 10.25))
            path.curve(
                to: NSPoint(x: 2.1, y: 11.6),
                controlPoint1: NSPoint(x: 0.8, y: 11.25),
                controlPoint2: NSPoint(x: 1.5, y: 11.6)
            )
            path.curve(to: NSPoint(x: 4.2, y: 11.6), controlPoint1: NSPoint(x: 2.6, y: 12.65), controlPoint2: NSPoint(x: 3.6, y: 12.75))
            path.curve(to: NSPoint(x: 5.9, y: 11.6), controlPoint1: NSPoint(x: 4.7, y: 11.1), controlPoint2: NSPoint(x: 5.4, y: 11.1))
            path.curve(to: NSPoint(x: 8, y: 11.6), controlPoint1: NSPoint(x: 6.4, y: 12.65), controlPoint2: NSPoint(x: 7.4, y: 12.75))
            path.curve(to: NSPoint(x: 9.7, y: 11.6), controlPoint1: NSPoint(x: 8.5, y: 11.1), controlPoint2: NSPoint(x: 9.2, y: 11.1))
            path.curve(to: NSPoint(x: 11.8, y: 11.6), controlPoint1: NSPoint(x: 10.2, y: 12.65), controlPoint2: NSPoint(x: 11.2, y: 12.75))
            path.curve(to: NSPoint(x: 13.5, y: 11.6), controlPoint1: NSPoint(x: 12.3, y: 11.1), controlPoint2: NSPoint(x: 13, y: 11.1))
            path.curve(to: NSPoint(x: 15.6, y: 11.6), controlPoint1: NSPoint(x: 14, y: 12.65), controlPoint2: NSPoint(x: 15, y: 12.75))
            path.curve(to: NSPoint(x: 17.3, y: 11.6), controlPoint1: NSPoint(x: 16.1, y: 11.1), controlPoint2: NSPoint(x: 16.8, y: 11.1))
            path.curve(to: NSPoint(x: 19.4, y: 11.6), controlPoint1: NSPoint(x: 17.8, y: 12.65), controlPoint2: NSPoint(x: 18.8, y: 12.75))
            path.curve(
                to: NSPoint(x: 21.2, y: 10.25),
                controlPoint1: NSPoint(x: 20.2, y: 11.6),
                controlPoint2: NSPoint(x: 21.2, y: 11.25)
            )
            path.curve(
                to: NSPoint(x: 19.8, y: 9.45),
                controlPoint1: NSPoint(x: 21.2, y: 9.55),
                controlPoint2: NSPoint(x: 20.45, y: 9.5)
            )
            path.line(to: NSPoint(x: 17.7, y: 5.1))
            path.curve(
                to: NSPoint(x: 17.1, y: 4.7),
                controlPoint1: NSPoint(x: 17.58, y: 4.85),
                controlPoint2: NSPoint(x: 17.38, y: 4.7)
            )
            path.line(to: NSPoint(x: 4.9, y: 4.7))
            path.curve(
                to: NSPoint(x: 4.3, y: 5.1),
                controlPoint1: NSPoint(x: 4.62, y: 4.7),
                controlPoint2: NSPoint(x: 4.42, y: 4.85)
            )
            path.line(to: NSPoint(x: 2.2, y: 9.45))
            path.curve(
                to: NSPoint(x: 0.8, y: 10.25),
                controlPoint1: NSPoint(x: 1.55, y: 9.5),
                controlPoint2: NSPoint(x: 0.8, y: 9.55)
            )
            path.close()

            // The M is an independent subpath, fully inside the tapered
            // wall. Even-odd filling leaves a true transparent aperture.
            path.move(to: NSPoint(x: 12.8, y: 5.9))
            path.line(to: NSPoint(x: 13.7, y: 5.9))
            path.line(to: NSPoint(x: 13.7, y: 7.9))
            path.line(to: NSPoint(x: 14.85, y: 6.45))
            path.line(to: NSPoint(x: 16, y: 7.9))
            path.line(to: NSPoint(x: 16, y: 5.9))
            path.line(to: NSPoint(x: 16.9, y: 5.9))
            path.line(to: NSPoint(x: 16.9, y: 9.3))
            path.line(to: NSPoint(x: 16, y: 9.3))
            path.line(to: NSPoint(x: 14.85, y: 8.05))
            path.line(to: NSPoint(x: 13.7, y: 9.3))
            path.line(to: NSPoint(x: 12.8, y: 9.3))
            path.close()

            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
