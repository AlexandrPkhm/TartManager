import AppKit
import Testing
@testable import TartManager

@Suite @MainActor struct MenuBarIconTests {
    @Test func menuBarIconIsAnAlphaTemplateWithAnInsetMark() throws {
        let image = MenuBarIcon.image

        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 22, height: 18))

        for scale in [CGFloat(1), 2] {
            let bitmap = rasterized(image, scale: scale)

            // The body stays filled at each backing scale, while the M and
            // external canvas retain genuine alpha transparency.
            #expect(alpha(at: NSPoint(x: 7, y: 7), in: bitmap, imageSize: image.size) > 0.95)
            #expect(alpha(at: NSPoint(x: 13.25, y: 8.5), in: bitmap, imageSize: image.size) < 0.05)
            #expect(alpha(at: NSPoint(x: 0, y: 0), in: bitmap, imageSize: image.size) < 0.05)
        }
    }

    private func rasterized(_ image: NSImage, scale: CGFloat) -> NSBitmapImageRep {
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: .alphaFirst,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.compositingOperation = .clear
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        context.compositingOperation = .sourceOver
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(at point: NSPoint, in bitmap: NSBitmapImageRep, imageSize: NSSize) -> CGFloat {
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / imageSize.width)
        // AppKit paths use a lower-left origin; bitmap pixel rows start at
        // the top, so invert y before reading the generated representation.
        let y = bitmap.pixelsHigh - 1 - Int(point.y * CGFloat(bitmap.pixelsHigh) / imageSize.height)
        return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }
}
