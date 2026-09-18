import Foundation

/// Everything the detail pane renders for the current selection.
/// Lives in its own file.
public struct VMDetails: Equatable, Sendable {
    public let entry: VMEntry
    public let config: VMConfigInfo?
    public let ip: String?
    public let fetchedAt: Date

    public init(entry: VMEntry, config: VMConfigInfo?, ip: String?, fetchedAt: Date) {
        self.entry = entry
        self.config = config
        self.ip = ip
        self.fetchedAt = fetchedAt
    }
}

/// Which `tart` subprocesses a detail refresh needs.
public struct VMDetailsPlan: Equatable, Sendable {
    public let fetchConfig: Bool
    public let fetchIP: Bool

    public init(fetchConfig: Bool, fetchIP: Bool) {
        self.fetchConfig = fetchConfig
        self.fetchIP = fetchIP
    }
}

/// Pure rules for the detail pane: which calls to make and what to publish.
/// Lives in TartKit so the decision layer is unit-tested; `AppModel` only
/// follows the plan and stores the config cache.
public enum VMDetailsResolver {
    /// The refresh plan for a selection. OCI rows never trigger `get`/`ip`
    /// (no config.json, no guest). The VM config is static in this slice
    /// (settings editing owns changes), so it is fetched once per selection
    /// and reused while the selection is unchanged — only the IP is rechecked
    /// per poll, and only for running local VMs.
    public static func plan(for entry: VMEntry, configIsCached: Bool) -> VMDetailsPlan {
        guard entry.isLocal else {
            return VMDetailsPlan(fetchConfig: false, fetchIP: false)
        }
        return VMDetailsPlan(fetchConfig: !configIsCached, fetchIP: entry.running)
    }

    /// Builds the payload. The IP is a running-local-only fact: anything else
    /// publishes nil and the view renders the non-error placeholder.
    public static func assemble(entry: VMEntry, config: VMConfigInfo?,
                                ip: String?, fetchedAt: Date) -> VMDetails {
        let resolvedIP = (entry.isLocal && entry.running) ? ip : nil
        return VMDetails(entry: entry, config: config, ip: resolvedIP, fetchedAt: fetchedAt)
    }
}
