import Foundation

/// Where Tart Manager embeds its own tart.
///
/// The packaged app carries the unchanged upstream `tart.app` at
/// `Contents/Helpers/tart.app`. A `swift run` build has none, so the lookup
/// returns `nil` and the bundled source reads as unavailable.
public enum BundledTartLocation {
    public static let relativeExecutablePath = "Contents/Helpers/tart.app/Contents/MacOS/tart"

    /// The bundled tart executable inside `bundleURL`, or `nil` when it is
    /// not an executable file.
    public static func executablePath(inAppBundle bundleURL: URL) -> String? {
        let path = bundleURL.appendingPathComponent(relativeExecutablePath).path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}
