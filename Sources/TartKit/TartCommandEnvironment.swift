import Foundation

/// The environment storage-touching tart invocations need to operate on the
/// configured storage. Scope: every tart operation that resolves VMs, caches,
/// or clones against the configured folder (TartClient in later slices). The
/// prerequisite `tart --version` probe from Issue 1 deliberately does NOT
/// receive this override — version detection is storage-independent.
public struct TartCommandEnvironment: Sendable {
    public let storagePath: String
    private let automaticCachePruningEnabled: Bool

    /// Manual cache maintenance also suppresses tart's low-space reclamation
    /// for app-launched commands so cached images remain until explicit cleanup.
    public init(storagePath: String, automaticCachePruningEnabled: Bool = true) {
        self.storagePath = storagePath
        self.automaticCachePruningEnabled = automaticCachePruningEnabled
    }

    /// Overrides passed to every storage-touching tart subprocess
    /// (merged over the process env by ProcessRunner).
    public var environment: [String: String] {
        var overrides = ["TART_HOME": storagePath]
        if !automaticCachePruningEnabled {
            overrides["TART_NO_AUTO_PRUNE"] = "1"
        }
        return overrides
    }
}
