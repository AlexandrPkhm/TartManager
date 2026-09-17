import Foundation

/// The result of checking the tart CLI prerequisite.
public enum TartPrerequisiteStatus: Equatable, Sendable {
    case ok(version: TartVersion, binaryPath: String)
    case missing
    case outdated(found: TartVersion, required: TartVersion, binaryPath: String)

    public var isSatisfied: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// Presentation-only guidance for unsatisfied prerequisite states: the
/// headline, detail, and shell command rendered by the banner.
///
/// Holds no domain constants — the required version in the outdated detail is
/// interpolated from the status payload (which originates at
/// `TartVersion.minimumSupported`).
public enum TartPrerequisiteGuidance {
    public static let installCommand = "brew install cirruslabs/cli/tart"
    public static let upgradeCommand = "brew upgrade cirruslabs/cli/tart"

    public static func guidance(for status: TartPrerequisiteStatus) -> TartPrerequisiteGuidanceInfo? {
        switch status {
        case .ok:
            return nil
        case .missing:
            return TartPrerequisiteGuidanceInfo(
                headline: "Tart is required",
                detail: "Tart Manager controls VMs through the tart CLI. Install it with Homebrew:",
                command: installCommand)
        case .outdated(let found, let required, _):
            return TartPrerequisiteGuidanceInfo(
                headline: "Tart is outdated",
                detail: "Tart Manager needs tart \(required) or newer; found \(found). Upgrading is recommended:",
                command: upgradeCommand)
        }
    }
}

/// Copyable guidance rendered by the prerequisite banner.
public struct TartPrerequisiteGuidanceInfo: Equatable, Sendable {
    public let headline: String
    public let detail: String
    public let command: String

    public init(headline: String, detail: String, command: String) {
        self.headline = headline
        self.detail = detail
        self.command = command
    }
}
