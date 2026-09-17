/// A semantic-version triple parsed from tart CLI output.
public struct TartVersion: Equatable, Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Floor for the wrapped surface. The JSON `list`/`get` output, `clone
    /// --concurrency`, `export`/`import`, `suspend`, and `prune --entries` all
    /// shipped well before tart 2.0.0. Domain constant — presentation types
    /// read it, never define it. One-line change if it is ever refined.
    public static let minimumSupported = TartVersion(major: 2, minor: 0, patch: 0)

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the first `X.Y.Z` triple found anywhere in `raw`,
    /// tolerating prefixes, suffixes, and surrounding whitespace.
    public static func parse(_ raw: String) -> TartVersion? {
        guard let match = raw.firstMatch(of: #/(\d+)\.(\d+)\.(\d+)/#) else { return nil }
        guard let major = Int(match.1),
              let minor = Int(match.2),
              let patch = Int(match.3) else { return nil }
        return TartVersion(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: TartVersion, rhs: TartVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}
