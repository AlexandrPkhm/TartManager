import Foundation

/// The single place that builds a child-process environment: the parent
/// environment overlaid with `overrides`. `ProcessRunner` and
/// `DetachedProcessLauncher` share this so their merge semantics cannot
/// drift (in particular: empty overrides leave `Process.environment`
/// unset, so the child inherits the parent environment directly).
public enum ProcessEnvironment {
    /// Returns `base` overlaid with `overrides`, or nil when there are no
    /// overrides (the caller then leaves `Process.environment` unset).
    public static func merged(
        overrides: [String: String],
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String]? {
        guard !overrides.isEmpty else { return nil }
        var merged = base
        for (key, value) in overrides { merged[key] = value }
        return merged
    }
}
