import os

/// Central os.Logger instances.
public extension Logger {
    /// Storage lifecycle events: availability transitions.
    static let storage = Logger(subsystem: "app.TartManager", category: "storage")
    /// Settings persistence events: validated choices and rejections.
    static let settings = Logger(subsystem: "app.TartManager", category: "settings")
    /// Stop lifecycle events: commands, completions, failures, reconciliations,
    /// and suppressed unknown-state cases.
    static let stop = Logger(subsystem: "app.TartManager", category: "stop")
    /// Suspend lifecycle events: commands, completions, failures,
    /// reconciliations, suppressed unknown-state cases, and stale-registry
    /// releases (review finding 8).
    static let suspend = Logger(subsystem: "app.TartManager", category: "suspend")
    /// Normalized operation failures: one line per presented error
    /// (operation, exit code, first stderr line, hint).
    static let errorReporting = Logger(subsystem: "app.TartManager", category: "errorReporting")
    /// Tart subprocess boundary (list/get/ip/run/stop): failures and timeouts.
    static let client = Logger(subsystem: "app.TartManager", category: "TartClient")
    /// Resource-editing lifecycle: apply/regenerate start, success, failure,
    /// and guard-trip rejections.
    static let resources = Logger(subsystem: "app.TartManager", category: "resources")
    /// Clone lifecycle events: guard refusals and job starts.
    static let clone = Logger(subsystem: "app.TartManager", category: "clone")
    /// Archive-import job lifecycle: start, pre-flight refusal, outcome, cleanup.
    static let importJob = Logger(subsystem: "app.TartManager", category: "importJob")
    /// Partial-import cleanup decisions, actions, and anomalies.
    static let importCleanup = Logger(subsystem: "app.TartManager", category: "importCleanup")
    /// Run-time host-memory over-commitment assessment: gather outcomes,
    /// degrade decisions (0 MB contributions, timeouts, missing inventory),
    /// and the final warn/proceed choice.
    static let overcommit = Logger(subsystem: "app.TartManager", category: "overcommit")
    /// Snapshot lifecycle events: export jobs, stopped-only refusals, sidecar
    /// writes, folder resolution (finding 12).
    static let snapshot = Logger(subsystem: "app.TartManager", category: "snapshot")
    /// Restore lifecycle events: pre-flight verdicts and refusals, per-stage
    /// notes, reconciled races, and failures with guidance + raw details.
    static let restore = Logger(subsystem: "app.TartManager", category: "restore")
    /// Create-from-IPSW job lifecycle: start, pre-flight refusal, outcome, cleanup.
    static let createJob = Logger(subsystem: "app.TartManager", category: "createJob")
    /// Create-from-IPSW cleanup decisions, actions, and anomalies.
    static let createCleanup = Logger(subsystem: "app.TartManager", category: "createCleanup")
    /// VM deletion lifecycle/audit — the most destructive operation in the
    /// app: start, outcome (with duration and normalized error), race
    /// no-ops, and every refusal.
    static let deleteVM = Logger(subsystem: "app.TartManager", category: "deleteVM")
    /// VM rename lifecycle: start, outcome, race no-ops, refusals.
    static let rename = Logger(subsystem: "app.TartManager", category: "rename")
    /// Replace-disk lifecycle — the audit record for the most destructive
    /// operation: refusals (with reason), job start with the VM name and the
    /// source path, and the success/failure outcome (finding 4).
    static let replaceDisk = Logger(subsystem: "app.TartManager", category: "replaceDisk")
    /// Registry auth lifecycle: login/logout start, success, failure, skips,
    /// and tart-unavailable aborts. Host and username are logged; the
    /// password never is.
    static let registries = Logger(subsystem: "app.TartManager", category: "registries")
    /// Shared-folders lifecycle: share-list persistence, the constructed run
    /// argv (counts/tags, not host paths), editor-gate refusals, and run
    /// failures that involve shares.
    static let sharedFolders = Logger(subsystem: "app.TartManager", category: "sharedFolders")
    /// App icon resolution: which layout supplied the icon and the fallback
    /// to the system application icon when none did.
    static let icon = Logger(subsystem: "app.TartManager", category: "icon")
    /// Guest-clipboard watchdog lifecycle: guest readiness polls, agent
    /// kickstarts, watchdog installs, and every degrade decision.
    static let clipboard = Logger(subsystem: "app.TartManager", category: "clipboard")
    /// In-app updater lifecycle: update checks, results, skips,
    /// postponements, installs, and refusals. Feed URLs and versions are
    /// public.
    static let updates = Logger(subsystem: "app.TartManager", category: "updates")
    /// Tart runtime lifecycle: source resolution, default-source
    /// decisions, switches, refusals, and bundled-tart verification. Paths
    /// are public, with the user home shown as `~`.
    static let tartRuntime = Logger(subsystem: "app.TartManager", category: "tartRuntime")
    /// Main-window and Dock lifecycle: open-window counts, activation-policy
    /// changes, Dock reopen decisions, and reopen failures.
    static let window = Logger(subsystem: "app.TartManager", category: "window")
}
