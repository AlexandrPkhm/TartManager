import Foundation

/// Detects the tart installed on this Mac (the `installed` source).
///
/// Detection order:
/// 1. Well-known Homebrew locations (GUI apps don't inherit the shell PATH)
/// 2. Each directory of the search PATH
///
/// A custom path and the bundled tart are not candidates here:
/// `PrerequisiteChecker` checks each source on its own and never falls back
/// from one source to another.
public struct TartLocator: Sendable {
    public let searchPath: String
    public let wellKnownLocations: [String]

    public static let homebrewLocations: [String] = [
        "/opt/homebrew/bin/tart",
        "/usr/local/bin/tart",
    ]

    public init(searchPath: String? = nil,
                wellKnownLocations: [String]? = nil) {
        self.searchPath = searchPath
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin"
        self.wellKnownLocations = wellKnownLocations ?? Self.homebrewLocations
    }

    /// Returns the first candidate that is an executable file, or nil.
    public func locate() -> String? {
        var candidates = wellKnownLocations
        candidates.append(contentsOf: searchPath
            .split(separator: ":")
            .map { "\($0)/tart" })
        return candidates.first { Self.isExecutable($0) }
    }

    static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
