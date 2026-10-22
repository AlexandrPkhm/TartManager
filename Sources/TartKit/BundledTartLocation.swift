import Foundation

/// Where Tart Manager embeds its own tart.
///
/// The packaged app carries the unchanged upstream `tart.app` at
/// `Contents/Helpers/tart.app`. A `swift run` build has none, so the lookup
/// returns `nil` and the bundled source reads as unavailable.
public enum BundledTartLocation {
    public static let relativeExecutablePath = "Contents/Helpers/tart.app/Contents/MacOS/tart"
    public static let relativeInfoPlistPath = "Contents/Helpers/tart.app/Contents/Info.plist"

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

    /// The version the bundled `tart.app` declares in its `Info.plist`
    /// (`CFBundleShortVersionString`), read without running it, so it is
    /// known even when the tart fails its checks. `nil` when the file is
    /// missing or the value is not `X.Y.Z`; the value goes into a license URL.
    public static func declaredVersion(inAppBundle bundleURL: URL) -> String? {
        let url = bundleURL.appendingPathComponent(relativeInfoPlistPath)
        guard let info = NSDictionary(contentsOf: url),
              let version = info["CFBundleShortVersionString"] as? String,
              version.wholeMatch(of: #/[0-9]+\.[0-9]+\.[0-9]+/#) != nil else { return nil }
        return version
    }
}
