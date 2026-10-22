import Foundation

/// The result of checking one tart source.
///
/// Every case names its source, so the banner, Settings, and diagnostics can
/// say which tart failed. `.invalidCustomPath` always belongs to the
/// `installed` source: a custom path applies only there.
public enum TartPrerequisiteStatus: Equatable, Sendable {
    case ok(version: TartVersion, binaryPath: String, source: TartSource)
    case outdated(found: TartVersion, required: TartVersion, binaryPath: String, source: TartSource)
    case missing(source: TartSource)
    case damaged(source: TartSource, reason: String)
    case invalidCustomPath(path: String)

    public var isSatisfied: Bool {
        if case .ok = self { return true }
        return false
    }

    public var source: TartSource {
        switch self {
        case .ok(_, _, let source), .outdated(_, _, _, let source),
             .missing(let source), .damaged(let source, _):
            return source
        case .invalidCustomPath:
            return .installed
        }
    }

    /// The version that ran, for `.ok` and `.outdated` only.
    public var version: TartVersion? {
        switch self {
        case .ok(let version, _, _): return version
        case .outdated(let found, _, _, _): return found
        case .missing, .damaged, .invalidCustomPath: return nil
        }
    }

    /// The tart path this status describes, when one is known.
    public var binaryPath: String? {
        switch self {
        case .ok(_, let path, _), .outdated(_, _, let path, _), .invalidCustomPath(let path):
            return path
        case .missing, .damaged:
            return nil
        }
    }

    /// One line for error reports and the About tab: version or state,
    /// source, then the path or reason.
    public var diagnosticLine: String {
        switch self {
        case .ok(let version, let path, let source):
            return "\(version) · \(source.rawValue) · \(path)"
        case .outdated(let found, _, let path, let source):
            return "\(found) (outdated) · \(source.rawValue) · \(path)"
        case .missing(let source):
            return "not found · \(source.rawValue)"
        case .damaged(let source, let reason):
            return "damaged · \(source.rawValue) · \(reason)"
        case .invalidCustomPath(let path):
            return "cannot run · installed · \(path)"
        }
    }
}

/// Presentation-only guidance for an unsatisfied active tart: the headline,
/// detail, optional shell command, and optional switch to the other source.
///
/// The copy depends on the source and the failure. The switch is offered only
/// when the other source checks as `.ok`, so a click always lands on a
/// working tart. Holds no domain constants — the required version in the
/// outdated detail is interpolated from the status payload (which originates
/// at `TartVersion.minimumSupported`).
public enum TartPrerequisiteGuidance {
    public static let installCommand = "brew install cirruslabs/cli/tart"
    public static let upgradeCommand = "brew upgrade cirruslabs/cli/tart"

    static let reinstallDetail = "Reinstall Tart Manager to restore it."

    public static func guidance(for report: TartRuntimeReport) -> TartPrerequisiteGuidanceInfo? {
        let switchTo: TartSource? = report.other?.isSatisfied == true ? report.other?.source : nil
        switch report.active {
        case .ok:
            return nil
        case .missing(.bundled):
            return TartPrerequisiteGuidanceInfo(
                headline: "Bundled tart is missing", detail: reinstallDetail,
                command: nil, switchTo: switchTo)
        case .damaged:
            return TartPrerequisiteGuidanceInfo(
                headline: "Bundled tart is damaged", detail: reinstallDetail,
                command: nil, switchTo: switchTo)
        case .missing(.installed):
            return TartPrerequisiteGuidanceInfo(
                headline: "Tart is not installed",
                detail: "Install tart with Homebrew, or choose a tart file in Settings → General:",
                command: installCommand, switchTo: switchTo)
        case .invalidCustomPath:
            return TartPrerequisiteGuidanceInfo(
                headline: "The selected tart cannot run",
                detail: "Choose another tart file in Settings → General.",
                command: nil, switchTo: switchTo)
        case .outdated(_, _, _, .bundled):
            return TartPrerequisiteGuidanceInfo(
                headline: "Tart is outdated",
                detail: "Update Tart Manager to get a newer bundled tart.",
                command: nil, switchTo: switchTo)
        case .outdated(let found, let required, _, .installed):
            return TartPrerequisiteGuidanceInfo(
                headline: "Tart is outdated",
                detail: "Tart Manager needs tart \(required) or newer; found \(found). Upgrading is recommended:",
                command: upgradeCommand, switchTo: switchTo)
        }
    }

    /// The banner button that switches to `source`.
    public static func switchLabel(for source: TartSource) -> String {
        switch source {
        case .bundled: return "Use bundled tart"
        case .installed: return "Use installed tart"
        }
    }
}

/// Copyable guidance rendered by the prerequisite banner.
public struct TartPrerequisiteGuidanceInfo: Equatable, Sendable {
    public let headline: String
    public let detail: String
    /// The shell command to copy, when the fix is a Homebrew command.
    public let command: String?
    /// The other source, when it checks as `.ok` and the banner can offer it.
    public let switchTo: TartSource?

    public init(headline: String, detail: String, command: String?, switchTo: TartSource? = nil) {
        self.headline = headline
        self.detail = detail
        self.command = command
        self.switchTo = switchTo
    }
}
