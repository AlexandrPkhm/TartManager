import Foundation

/// One row of `tart list` — a local VM or a pulled OCI image entry.
/// `diskSize`/`diskUsage` are deliberately unit-neutral: the spike could not
/// confirm tart's units, so the model avoids baking "GB"/"bytes" into API
/// names. Unit formatting lives in the view (VMRowView); a later unit
/// correction is display-only.
public struct VMEntry: Equatable, Hashable, Identifiable, Sendable {
    public let name: String
    /// Raw source string; `"local"` identifies runnable VMs.
    public let source: String
    public let running: Bool
    /// Status string exactly as tart reports it (`stopped`, `running`, …).
    public let state: String
    /// Allocated disk (tart's `Disk` key).
    public let diskSize: Double
    /// On-disk usage (tart's `Size` key).
    public let diskUsage: Double
    public let accessed: Date?
    /// Guest OS (`"darwin"` | `"linux"`), attached by `TartClient.list()` from
    /// the VM's on-disk `config.json` — `tart list` itself omits it. nil for
    /// OCI rows and when the config could not be read.
    public let guestOS: String?

    public var id: String { name }
    public var isLocal: Bool { source == "local" }

    /// Whether tart can suspend this VM. macOS guests only: tart 2.32 refuses
    /// both `run --suspendable` and `suspend` for every other guest. The one
    /// predicate shared by the run configuration and the Suspend affordances.
    public var supportsSuspend: Bool { VMGuestOS.supportsSuspend(guestOS) }

    /// Whether the app may run `tart set`-family edits on this VM.
    /// The single source of truth for the stopped-only gate — the view and
    /// both AppModel guards share it so the copies cannot drift.
    public var canEditResources: Bool {
        !running && state.lowercased() != "suspended"
    }

    /// Whether Replace Disk may be offered/run: the VM is neither running nor
    /// suspended. The single source of truth for the replace-disk state gate,
    /// shared by VMRowView's menu items and ReplaceDiskGuard (finding 1).
    public var canReplaceDisk: Bool {
        !running && !isSuspended
    }

    public init(name: String, source: String, running: Bool, state: String,
                diskSize: Double, diskUsage: Double, accessed: Date?,
                guestOS: String? = nil) {
        self.name = name
        self.source = source
        self.running = running
        self.state = state
        self.diskSize = diskSize
        self.diskUsage = diskUsage
        self.accessed = accessed
        self.guestOS = guestOS
    }
}

extension VMEntry: Decodable {
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case source = "Source"
        case running = "Running"
        case state = "State"
        case diskSize = "Disk"
        case diskUsage = "Size"
        case accessed = "Accessed"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawRunning = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
        let rawState = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(String.self, forKey: .source)
        // Suspended is a distinct lifecycle state, not "running" (PRD Local
        // VM state machine: running → suspended → running). Normalizing at
        // decode keeps every consumer — the row branches, the run/stop/
        // suspend pre-checks, and `RunCoordinator.reconcile`'s eviction —
        // correct without per-site checks, even if tart's `Running` field
        // stays true for a suspended VM (Task 0's finding).
        running = rawRunning && !SuspendedStateReporting.isSuspendedState(rawState)
        state = rawState
        diskSize = try container.decodeIfPresent(Double.self, forKey: .diskSize) ?? 0
        diskUsage = try container.decodeIfPresent(Double.self, forKey: .diskUsage) ?? 0
        accessed = try container.decodeIfPresent(Date.self, forKey: .accessed)
        // `tart list` omits the guest OS; `TartClient.list()` attaches it
        // from the VM's on-disk config after decoding.
        guestOS = nil
    }
}

/// Spike-determined facts about how the installed tart reports a suspended
/// VM (Task 0 of the suspend slice). Single source of truth for the state
/// mapping and the issue's fallback.
public enum SuspendedStateReporting {
    /// The `State` string tart reports for a suspended VM. Task 0 Step 3
    /// sets this to the string recorded on the host; the pre-spike default
    /// assumes `"suspended"`.
    public static let suspendedStateLiteral = "suspended"

    /// True when tart's `State` distinguishes suspended from stopped.
    /// Task 0's spike on the real host (tart 2.32) recorded a distinct
    /// `"suspended"` state, so this is true: only suspended rows label the
    /// primary action Resume, stopped rows keep Run. When false (a tart
    /// that reports suspended as stopped), the issue's fallback applies —
    /// suspended is treated as stopped and the primary action is offered
    /// as Resume on both, because `tart run` resumes a parked session and
    /// cold-boots a stopped VM, so one action covers both states.
    public static let distinguishesSuspended = true

    /// Case-insensitive match against the spike-recorded literal.
    public static func isSuspendedState(_ raw: String) -> Bool {
        raw.lowercased() == suspendedStateLiteral.lowercased()
    }
}

extension VMEntry {
    /// Returns a copy with the guest OS attached — the inventory enrichment
    /// step (`TartClient.list()`) that keeps every downstream consumer (run
    /// configuration, Suspend affordances) off the raw `config.json`.
    public func withGuestOS(_ os: String?) -> VMEntry {
        VMEntry(name: name, source: source, running: running, state: state,
                diskSize: diskSize, diskUsage: diskUsage, accessed: accessed,
                guestOS: os)
    }

    /// True when tart's list reports this VM as suspended (per Task 0).
    public var isSuspended: Bool {
        SuspendedStateReporting.isSuspendedState(state)
    }

    /// True for a local VM that is neither running nor suspended — the only
    /// state in which delete/rename are allowed (PRD US 19/20 AC2). The one
    /// predicate every gate uses: the model guards, the job pre-flights, and
    /// the context menu. `running` is already decode-normalized for suspended
    /// entries; the explicit `!isSuspended` keeps memberwise-constructed
    /// entries safe and states the intent once instead of per call site.
    public var isStoppedLocal: Bool {
        isLocal && !running && !isSuspended
    }

    /// Primary-action label on a non-running row: Resume for suspended
    /// VMs, or — under the issue's fallback (`distinguishesSuspended ==
    /// false`) — Resume on both, because a stopped row may hide a parked
    /// session.
    public func primaryActionLabel(distinguishesSuspended: Bool) -> String {
        (isSuspended || !distinguishesSuspended) ? "Resume" : "Run"
    }
}
