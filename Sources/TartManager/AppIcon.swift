import AppKit
import os

/// Shares the compiled compatibility icon between bare SwiftPM launches
/// (via `AppDelegate`) and Settings → About. Packaged apps let macOS render
/// the layered Icon Composer asset in the Dock.
///
/// Resolution never crashes the app. The icon is looked up in the two
/// supported layouts via `AppIconSource`: the packaged `.app`
/// (`Contents/Resources/AppIcon.icns`, produced by `Scripts/package.sh`) and
/// the bare `swift run` layout (the SwiftPM resource bundle next to the
/// executable). SwiftPM's generated `Bundle.module` accessor is deliberately
/// avoided: it traps at first access when the resource bundle is absent,
/// which is exactly the packaged layout (the app would crash in
/// `applicationDidFinishLaunching`). When no candidate holds a valid icon,
/// the app logs the miss and falls back to the system application icon.
@MainActor
enum AppIcon {
    static let image: NSImage = {
        let candidates = AppIconSource.candidateURLs(
            resourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL
        )
        for url in candidates {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        Logger.icon.error(
            "No candidate location holds a valid AppIcon.icns; falling back to the system application icon."
        )
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: .zero)
    }()
}
