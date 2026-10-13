import Foundation
import Combine

/// A long-running operation's observable record.
public struct JobInfo: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case clone(name: String, source: String)
        case importArchive(name: String, path: String)
        case exportSnapshot(vm: String)
        case restoreSnapshot(vm: String)
        case createFromIPSW(name: String)
        case deleteVM(name: String)
        case replaceDisk(name: String, path: String)
        case prune

        /// The guarded resource name: one heavy job per target at a time.
        /// Derived here so call sites can never pass a mismatched pair
        /// (finding 5).
        public var target: String {
            switch self {
            case .clone(let name, _): return name
            case .importArchive(let name, _): return name
            case .exportSnapshot(let vm): return vm
            case .restoreSnapshot(let vm): return vm
            case .createFromIPSW(let name): return name
            case .deleteVM(let name): return name
            case .replaceDisk(let name, _): return name
            case .prune:
                return "prune:caches"   // namespaced single-flight key — never a VM name (finding 5)
            }
        }

        /// The tart subcommand label used in normalized failures (finding 16).
        public var operation: String {
            switch self {
            case .clone: return "clone"
            case .importArchive: return "import"
            case .exportSnapshot: return "export"
            case .restoreSnapshot: return "restore"
            case .createFromIPSW: return "create"
            case .deleteVM: return "delete"
            case .replaceDisk: return "set"
            case .prune:
                return "prune"          // failure-normalization label (finding 8)
            }
        }

        /// Disk-need estimate for the pre-flight space gate (nil = no gate).
        /// Imports carry no fixed estimate here: their need derives from the
        /// archive's actual file size via `DiskSpacePolicy.importVerdict`.
        /// Export estimates need the VM's on-disk size — use
        /// `DiskSpacePolicy.exportVerdict(vmDiskUsageGB:freeBytes:)` (Issue 14).
        /// Restore's composite estimate needs data the case does not carry —
        /// `SnapshotRestoreJob` pre-flights instead. The create-from-IPSW
        /// estimate is draft-level data — computed per-draft by
        /// `DiskSpacePolicy` in the preflight; the kind carries no estimate.
        public var estimatedDiskNeedBytes: Int64? {
            switch self {
            case .clone: return DiskSpacePolicy.remoteImageEstimateBytes
            case .importArchive, .exportSnapshot, .restoreSnapshot: return nil
            case .createFromIPSW: return nil
            case .deleteVM: return nil
            // No estimate — the source file is chosen ad hoc; Story 14's
            // space pre-check covers clone/import/export only.
            case .replaceDisk: return nil
            case .prune:
                return nil              // prune frees space — no pre-flight gate
            }
        }

        /// Whether the job may be cancelled from the UI. Restore is excluded:
        /// once its delete stage begins, aborting the pipeline would strand
        /// the VM in the deleted state while the job claims "cancelled".
        /// Deletion is excluded too: killing a partially removed VM directory
        /// halfway would leave the ghost entry the PRD forbids. The
        /// typed-name confirmation is the only safe gate for either.
        /// Replace-disk is excluded as well: mid-copy termination would
        /// leave the disk half-replaced (unbootable or silently partial).
        /// Prune is safely cancellable: partial prunes merely free less.
        public var isCancellable: Bool {
            switch self {
            case .restoreSnapshot, .deleteVM, .replaceDisk: return false
            case .clone, .importArchive, .exportSnapshot, .createFromIPSW, .prune: return true
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case running
        case completed
        case failed
        case cancelled
    }

    public let id: UUID
    public let kind: Kind
    public let createdAt: Date
    public var phase: Phase
    public var progress: PullProgress?
    public var error: TartOperationError?
    public var summary: String?

    /// Completion summaries are capped at presentation size when buffered
    /// (enforced inside JobContext.reportSummary — finding 7).
    public static let summaryMaxLength = 240

    init(id: UUID = UUID(), kind: Kind, createdAt: Date = Date(),
         phase: Phase = .running, progress: PullProgress? = nil,
         error: TartOperationError? = nil, summary: String? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.phase = phase
        self.progress = progress
        self.error = error
        self.summary = summary
    }
}

/// Handed to job bodies: report progress, register a cancel action, read the cancel flag.
public final class JobContext: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellators: [@Sendable () -> Void] = []
    private var _cancelled = false

    public let report: @Sendable (PullProgress) -> Void

    /// Buffers a completion summary (capped at `JobInfo.summaryMaxLength`).
    /// The JobManager attaches it to the job record only when the body
    /// finishes successfully; failed or cancelled jobs discard it.
    public let reportSummary: @Sendable (String) -> Void

    init(report: @escaping @Sendable (PullProgress) -> Void,
         reportSummary: @escaping @Sendable (String) -> Void = { _ in }) {
        self.report = report
        self.reportSummary = reportSummary
    }

    public func registerCancel(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        cancellators.append(action)
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func performCancel() {
        lock.lock()
        _cancelled = true
        let actions = cancellators
        lock.unlock()
        actions.forEach { $0() }
    }
}

/// Executes long-running operations as observable, cancellable jobs.
@MainActor
public final class JobManager: ObservableObject {
    @Published public private(set) var jobs: [JobInfo] = []

    /// Called on the main actor after every phase transition (app wiring:
    /// failures → error sheet; terminal phases → inventory refresh).
    public var onStateChange: (@MainActor (JobInfo) -> Void)?

    /// Targets with an active job; the create sheet consults this so
    /// in-flight names are unavailable before tart knows about them
    /// (finding 4).
    public private(set) var runningTargets: Set<String> = []

    /// Names with a running job — pre-flight guards consult this so the
    /// dialogs and the manager agree on availability (a duplicate-target
    /// start is refused up front with visible feedback instead of a silent
    /// nil).
    public var activeTargets: Set<String> { runningTargets }

    private var contexts: [UUID: JobContext] = [:]

    /// Completion summaries buffered by running job bodies. Attached to the
    /// job record only during the successful terminal transition; removed
    /// (discarded) on failure/cancellation (finding 3).
    private var pendingSummaries: [UUID: String] = [:]

    public enum StartResult: Equatable {
        case started(JobInfo)
        case duplicateTarget(name: String)
    }

    public init() {}

    /// Starts a job for `kind` (its target is derived — finding 5). A
    /// duplicate target is refused with an observable `.duplicateTarget`
    /// result the caller surfaces (finding 4).
    /// Background maintenance passes `.utility`; user actions retain the
    /// default `.userInitiated` detached-task priority.
    /// Normal jobs reserve their targets immediately but wait for active
    /// cache cleanup before executing their bodies. Cancellation while
    /// waiting finishes without spawning a subprocess.
    @discardableResult
    public func start(kind: JobInfo.Kind,
                      priority: TaskPriority = .userInitiated,
                      body: @escaping @Sendable (JobContext) throws -> Void) -> StartResult {
        let target = kind.target
        guard !runningTargets.contains(target) else {
            return .duplicateTarget(name: target)
        }
        runningTargets.insert(target)

        let id = UUID()
        let info = JobInfo(id: id, kind: kind)
        jobs.append(info)

        let context = JobContext(
            report: { [weak self] progress in
                Task { @MainActor in
                    self?.updateJob(id: id) {
                        if $0.progress != progress { $0.progress = progress }
                    }
                }
            },
            reportSummary: { [weak self] summary in
                let capped = String(summary.prefix(JobInfo.summaryMaxLength))
                Task { @MainActor in
                    self?.pendingSummaries[id] = capped
                }
            })
        contexts[id] = context

        Task.detached(priority: priority) { [weak self] in
            let outcome: JobInfo.Phase
            let failure: TartOperationError?
            do {
                if kind != .prune {
                    var reportedWaiting = false
                    while !context.isCancelled {
                        let pruning = await MainActor.run { [weak self] in
                            self?.runningTargets.contains(JobInfo.Kind.prune.target) ?? false
                        }
                        guard pruning else { break }
                        if !reportedWaiting {
                            context.report(PullProgress(fraction: nil, note: "Waiting for cache cleanup…"))
                            reportedWaiting = true
                        }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    if reportedWaiting, !context.isCancelled {
                        context.report(PullProgress(fraction: nil, note: nil))
                    }
                }
                if !context.isCancelled { try body(context) }
                outcome = context.isCancelled ? .cancelled : .completed
                failure = nil
            } catch let raw as TartClientError {
                outcome = .failed
                failure = raw.normalized
            } catch {
                // finding 16: unknown failures carry the kind's operation
                // label ("clone"), never a bare "job".
                outcome = .failed
                failure = TartClientError.commandFailed(
                    command: kind.operation, exitCode: -1, stdout: "",
                    stderr: "\(error)").normalized
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.runningTargets.remove(target)
                self.contexts.removeValue(forKey: id)
                let summary = self.pendingSummaries.removeValue(forKey: id)
                self.updateJob(id: id) { job in
                    job.phase = outcome
                    job.error = failure
                    if outcome == .completed {
                        job.summary = summary   // attached atomically with the phase
                    }
                }
                if let info = self.jobs.first(where: { $0.id == id }) {
                    self.onStateChange?(info)   // observers see the summary (finding 3)
                }
            }
        }
        return .started(info)
    }

    public func cancel(id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].phase == .running,
              jobs[index].kind.isCancellable else { return } // restore is not cancellable
        // Terminate via registered cancellators; the body exits and marks
        // the phase. StreamingProcess's SIGKILL escalation (Task 2) bounds
        // how long a cancelled body may take (finding 9).
        contexts[id]?.performCancel()
    }

    public func dismiss(id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    /// Test support (finding 15): quiescence polling for tests. Internal —
    /// visible only to `@testable` consumers, not part of the public API.
    func awaitIdle(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !jobs.contains(where: { $0.phase == .running }) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Pre-flight space verdict for a prospective job of `kind` against a
    /// cached free-bytes probe. The PRD assigns pre-flight estimates and
    /// warnings to the Job Manager (finding 8); nil = unknown, no gate.
    public static func preflightSpace(kind: JobInfo.Kind,
                                      freeBytes: Int64?) -> DiskSpacePolicy.Verdict? {
        guard let freeBytes, let need = kind.estimatedDiskNeedBytes, need > 0 else {
            return nil
        }
        return DiskSpacePolicy.verdict(freeBytes: freeBytes, estimatedNeedBytes: need)
    }

    private func updateJob(id: UUID, _ mutate: (inout JobInfo) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }
}

extension JobManager {
    /// The one clone-job body shared by remote-image creates and local-VM
    /// clones — extracted from AppModel so the job outcome behavior is DRY
    /// and testable (finding 4). The body owns the streaming subprocess via
    /// `TartClient.clone` (progress parsing, cancellation wiring, and the
    /// standard `commandFailed` normalization are the client's) and returns
    /// nil only when the manager refuses a duplicate target.
    @discardableResult
    public func startClone(source: String, to name: String,
                           using client: TartClient) -> JobInfo? {
        let kind = JobInfo.Kind.clone(name: name, source: source)
        switch start(kind: kind, body: { context in
            _ = try client.clone(
                source: source, to: name,
                onProgress: { context.report($0) },
                registerCancel: { context.registerCancel($0) })
        }) {
        case .started(let job):
            return job
        case .duplicateTarget:
            return nil
        }
    }
}
