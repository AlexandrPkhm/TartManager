import Foundation

/// Resolves the path of the tart binary.
///
/// Resolution order:
/// 1. The explicit path (Settings override / tests)
/// 2. Well-known Homebrew locations (GUI apps don't inherit the shell PATH)
/// 3. Each directory of the search PATH
public struct TartLocator: Sendable {
    public let explicitPath: String?
    public let searchPath: String
    public let wellKnownLocations: [String]

    public static let homebrewLocations: [String] = [
        "/opt/homebrew/bin/tart",
        "/usr/local/bin/tart",
    ]

    public init(explicitPath: String? = nil,
                searchPath: String? = nil,
                wellKnownLocations: [String]? = nil) {
        self.explicitPath = explicitPath
        self.searchPath = searchPath
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin"
        self.wellKnownLocations = wellKnownLocations ?? Self.homebrewLocations
    }

    /// Returns the first candidate that is an executable file, or nil.
    public func locate() -> String? {
        var candidates: [String] = []
        if let explicitPath { candidates.append(explicitPath) }
        candidates.append(contentsOf: wellKnownLocations)
        candidates.append(contentsOf: searchPath
            .split(separator: ":")
            .map { "\($0)/tart" })
        return candidates.first { Self.isExecutable($0) }
    }

    static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
