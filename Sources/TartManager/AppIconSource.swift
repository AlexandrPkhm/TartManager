import Foundation

/// Pure, stateless resolution of the candidate locations for the bundled
/// `AppIcon.icns`, ordered most specific first.
///
/// Tart Manager ships in two layouts:
/// - the packaged `.app` assembled by `Scripts/package.sh`, where the icon is
///   copied to `Contents/Resources/AppIcon.icns` (see docs/DEPLOYMENT.md →
///   Packaging); and
/// - the bare `swift run` / `swift build` binary, where SwiftPM materializes
///   the resource as `<Target>_<Package>.bundle/Contents/Resources/AppIcon.icns`
///   in a bundle next to the executable.
///
/// SwiftPM's generated `Bundle.module` accessor is deliberately not used
/// here: it traps with `fatalError` at first access whenever the resource
/// bundle is absent, which is exactly the packaged-app layout. Resolving by
/// candidate URLs keeps the app launchable in both layouts.
enum AppIconSource {
    /// Packaged apps keep the system-rendered icon and its appearance variants.
    /// Only bare SwiftPM executables need a manually installed Dock image.
    static func needsRuntimeIcon(bundleURL: URL) -> Bool {
        bundleURL.pathExtension.lowercased() != "app"
    }

    /// Resource filename shared by both layouts.
    static let iconFileName = "AppIcon.icns"

    /// Ordered candidate URLs for the bundled icon.
    ///
    /// - Parameters:
    ///   - resourceURL: The running bundle's resource directory
    ///     (`Contents/Resources` for a packaged app, `nil` for a bare
    ///     executable).
    ///   - executableURL: The running executable's URL, used to locate
    ///     SwiftPM resource bundles adjacent to the binary.
    ///   - fileManager: Injected for tests.
    /// - Returns: Candidate URLs; callers probe them in order and stop at the
    ///   first URL that yields a valid icon.
    static func candidateURLs(
        resourceURL: URL?,
        executableURL: URL?,
        fileManager: FileManager = .default
    ) -> [URL] {
        var candidates: [URL] = []

        // Packaged layout: `Contents/Resources/AppIcon.icns`.
        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent(iconFileName))
        }

        guard let executableURL else { return candidates }
        let executableDirectory = executableURL.deletingLastPathComponent()

        // An icon placed directly next to the binary (unbundled layout).
        candidates.append(executableDirectory.appendingPathComponent(iconFileName))

        // SwiftPM resource bundles next to the executable, e.g.
        // `TartManager_TartManager.bundle/Contents/Resources/AppIcon.icns`.
        let entries = (try? fileManager.contentsOfDirectory(
            at: executableDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for entry in entries.sorted(by: { $0.path < $1.path })
        where entry.pathExtension == "bundle" {
            candidates.append(
                entry
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent(iconFileName)
            )
        }

        return candidates
    }
}
