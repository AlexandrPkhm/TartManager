import Foundation

/// Fail-fast validation for the local-clone flow, mirroring tart's rules so
/// the UI blocks invalid input before any subprocess spawns (issue
/// How-to-Verify Automated: uniqueness pre-validation + running-source
/// refusal).
public enum CloneGuard {
    /// Why the destination name is unusable.
    public enum NameIssue: Equatable, Sendable {
        case empty
        /// Mirrors tart's destination-name rules: no path separators, no
        /// "."/"..", no leading "-" (would parse as a CLI flag) (finding 5).
        case invalidSyntax
        /// A local VM or OCI image with this name exists, or an in-flight
        /// job already targets it.
        case taken
    }

    /// Why the source VM cannot be cloned.
    public enum SourceIssue: Equatable, Sendable {
        /// Only local VMs can be cloned (OCI images are pulled, not duplicated).
        case notLocal
        /// tart refuses to clone a running VM; the source must be stopped
        /// first (AC-2).
        case running
    }

    /// True when the name may be passed to tart. The character set delegates
    /// to the app's existing mirror of tart's naming rules (`VMNameRules`),
    /// so the clone dialog and the create dialog can never disagree on a
    /// name's characters; `.` and `..` (traversal names) are additionally
    /// rejected up front.
    public static func isValidNameSyntax(_ name: String) -> Bool {
        VMNameRules.isValid(name) && name != "." && name != ".."
    }

    /// nil when the name is usable; otherwise the first blocking issue.
    public static func validateName(_ name: String, taken: Set<String>) -> NameIssue? {
        if name.isEmpty { return .empty }
        if !isValidNameSyntax(name) { return .invalidSyntax }
        if taken.contains(name) { return .taken }
        return nil
    }

    /// nil when the source may be cloned; otherwise the blocking issue.
    public static func validateSource(_ source: VMEntry) -> SourceIssue? {
        if !source.isLocal { return .notLocal }
        if source.running { return .running }
        return nil
    }
}
