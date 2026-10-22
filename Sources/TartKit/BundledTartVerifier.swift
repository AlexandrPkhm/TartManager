import Foundation
import Security

/// The result of checking the bundled tart's code signature.
public enum BundledTartVerification: Equatable, Sendable {
    case valid
    case damaged(reason: String)
}

/// Checks that the bundled tart is the unchanged upstream build.
///
/// The check is static (`SecStaticCodeCheckValidity`), so it spawns no
/// process: a damaged binary is never run. When the executable lives inside
/// an `.app` (the `tart.app` helper), the whole app bundle is checked, which
/// covers its resources, entitlements, and provisioning profile. The
/// requirement pins the upstream Developer ID team.
public struct BundledTartVerifier: Sendable {
    /// The Developer ID team that signs upstream tart (observed on tart
    /// 2.32.1, `com.github.cirruslabs.tart`).
    public static let expectedTeamIdentifier = "9M2P8L4D89"

    public let requiredTeamIdentifier: String

    public init(requiredTeamIdentifier: String = Self.expectedTeamIdentifier) {
        self.requiredTeamIdentifier = requiredTeamIdentifier
    }

    public func verify(executablePath: String) -> BundledTartVerification {
        guard FileManager.default.fileExists(atPath: executablePath) else {
            return .damaged(reason: "The bundled tart file is missing.")
        }
        let target = Self.enclosingAppBundle(of: executablePath) ?? URL(fileURLWithPath: executablePath)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(target as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return .damaged(reason: "Cannot read the code signature (\(Self.describe(createStatus))).")
        }
        let requirementText =
            "anchor apple generic and certificate leaf[subject.OU] = \"\(requiredTeamIdentifier)\""
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            requirementText as CFString, [], &requirement)
        guard requirementStatus == errSecSuccess, let requirement else {
            return .damaged(reason: "Cannot build the signature requirement (\(Self.describe(requirementStatus))).")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        switch status {
        case errSecSuccess:
            return .valid
        case errSecCSUnsigned:
            return .damaged(reason: "The bundled tart is not signed.")
        case errSecCSReqFailed:
            return .damaged(reason: "The bundled tart is not signed by team \(requiredTeamIdentifier).")
        default:
            return .damaged(reason: "The code signature is invalid (\(Self.describe(status))).")
        }
    }

    /// The nearest ancestor folder whose name ends in `.app`, if any.
    static func enclosingAppBundle(of path: String) -> URL? {
        var url = URL(fileURLWithPath: path).deletingLastPathComponent()
        while url.path != "/" && !url.path.isEmpty {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func describe(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "\(message), \(status)"
    }
}
