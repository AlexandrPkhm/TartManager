import AppKit

/// Shares the full-resolution, multiscale charcoal icon between the Dock and About sheet.
@MainActor
enum AppIcon {
    static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("The bundled AppIcon.icns resource is missing or invalid.")
        }
        return image
    }()
}
