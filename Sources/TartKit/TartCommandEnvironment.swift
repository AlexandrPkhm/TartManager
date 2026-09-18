import Foundation

/// The environment storage-touching tart invocations need to operate on the
/// configured storage. Scope: every tart operation that resolves VMs, caches,
/// or clones against the configured folder (TartClient in later slices). The
/// prerequisite `tart --version` probe from Issue 1 deliberately does NOT
/// receive this override — version detection is storage-independent.
public struct TartCommandEnvironment: Sendable {
    public let storagePath: String

    public init(storagePath: String) {
        self.storagePath = storagePath
    }

    /// Overrides passed to every storage-touching tart subprocess
    /// (merged over the process env by ProcessRunner).
    public var environment: [String: String] {
        ["TART_HOME": storagePath]
    }
}
