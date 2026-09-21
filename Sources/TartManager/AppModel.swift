import SwiftUI
import TartKit
import os
import Combine

/// Bridges the async `TartClient.stop` into the synchronous restore pipeline
/// (the job body blocks on subprocess completion, like `waitForExit`). Bounded
/// by `TartClient.stopCommandTimeout` (90 s) — a wedged stop can block at
/// most that long. The only async→sync bridge in the restore path.
private final class SyncResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, Error>?

    func set(_ result: Result<Void, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }

    var result: Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Observable app-wide state: settings, tart prerequisite, storage availability.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var appearance: AppAppearance {
        didSet { settings.appearance = appearance }
    }
    @Published var prerequisite: TartPrerequisiteStatus?
    @Published var isCheckingPrerequisite = false
    @Published var storageAvailability: StorageAvailability =
        .unavailable(path: StorageLocationValidator.defaultPath, reason: .missing)

    private let checker = PrerequisiteChecker()

    /// One-time first-run reminders for IPSW-created VMs: flagged on create
    /// completion, consumed when the VM first runs.
    let firstRunReminder: FirstRunReminderStore

    init(settings: AppSettings = AppSettings(),
         firstRunReminder: FirstRunReminderStore = FirstRunReminderStore(defaults: .standard)) {
        self.settings = settings
        self.appearance = settings.appearance
        self.firstRunReminder = firstRunReminder
        // Poll failures re-probe storage availability: an unmounted volume
        // flips the app to the dedicated unavailable state without a restart,
        // and transient failures (availability unchanged) leave the last
        // inventory in place. [weak self]: no retain cycle.
        inventoryService.onFetchFailure = { [weak self] _ in
            self?.refreshAvailability()
        }
        // Issue 9 (finding 1 + finding 14): job terminal phases refresh the
        // inventory (coalesced) and failures present through the standard
        // sheet; the free-space probe rides the poll.
        jobManager.onStateChange = { [weak self] job in
            switch job.phase {
            case .failed:
                if let error = job.error {
                    self?.present(error)
                }
                Task { await self?.inventoryService.refreshIfStale() }
            case .completed:
                if case .createFromIPSW(let name) = job.kind {
                    self?.firstRunReminder.flag(name)
                }
                Task { await self?.inventoryService.refreshIfStale() }
            case .cancelled:
                Task { await self?.inventoryService.refreshIfStale() }
            case .running:
                break
            }
        }
        // Every inventory change reconciles the run registry: entries whose
        // child exited or whose VM the poll reports stopped are evicted, so
        // run → stop → run keeps working for the app's lifetime.
        inventoryService.$inventory
            .sink { [weak self] inventory in
                guard let self, let inventory else { return }
                self.runCoordinator.reconcile(with: inventory.localVMs)
                self.refreshStorageFreeBytes()   // Issue 9: cached probe (finding 14)
                // One-time first-run semantics: a flagged VM is unflagged the
                // moment the inventory first observes it running; names that
                // left the inventory (deleted VMs) are pruned so no stale
                // reminder lingers.
                for vm in inventory.localVMs where vm.running {
                    self.firstRunReminder.unflag(vm.name)
                }
                self.firstRunReminder.prune(
                    keeping: Set(inventory.localVMs.map(\.name)))
            }
            .store(in: &cancellables)
        // Leftover run logs from a launch whose window never completed
        // (app killed mid-launch) are swept at app start.
        RunCoordinator.cleanupStaleLogs()
        // The detail pane's refresh trigger: views observe AppModel only,
        // so every poll result is mirrored into a published property.
        inventoryObserver = inventoryService.$inventory.sink { [weak self] inventory in
            guard let self else { return }
            self.inventory = inventory
            if let inventory {
                self.select(WorkspaceSelection.resolve(
                    preferredName: self.selectedVM?.name ?? self.settings.selectedVMName,
                    localVMs: inventory.localVMs))
            }
        }
        refreshAvailability()
        rewireInventoryFetch()
    }

    var requiresOnboarding: Bool { settings.storagePath == nil }

    /// The environment every storage-touching tart operation in this app must use.
    var commandEnvironment: TartCommandEnvironment? {
        guard let path = settings.storagePath else { return nil }
        return TartCommandEnvironment(storagePath: path)
    }

    let inventoryService = InventoryService(fetch: { [] })

    /// The client for the current state, or nil while unsatisfied.
    var makeTartClient: () -> TartClient? {
        {
            guard let path = self.settings.storagePath,
                  let prerequisite = self.prerequisite,
                  case .ok(_, let binaryPath) = prerequisite else { return nil }
            return TartClient(binaryPath: binaryPath,
                              environment: TartCommandEnvironment(storagePath: path).environment)
        }
    }

    /// Rewire the inventory fetch from current state (call after any change).
    /// Captures `self` weakly so `AppModel ↔ InventoryService ↔ fetch` never
    /// forms a retain cycle (finding 12). Reports the precondition failure
    /// with the dedicated `InventoryFetchError` — never a fabricated
    /// `TartClientError` (finding 7).
    private func rewireInventoryFetch() {
        inventoryService.updateFetch { [weak self] in
            guard let self, let client = self.makeTartClient() else {
                throw InventoryFetchError.unavailable
            }
            let entries = try client.list()
            // Re-probe availability after a successful fetch (a cheap stat),
            // mirroring the failure-side re-probe in init: a re-mounted volume
            // recovers the list within one poll cycle instead of waiting for a
            // manual Retry.
            Task { @MainActor [weak self] in self?.refreshAvailability() }
            return entries
        }
    }

    let runCoordinator = RunCoordinator()

    /// Re-establishes and then keeps Tart clipboard sharing alive after
    /// every app-launched run: kicks the guest agent immediately and
    /// installs the guest-side watchdog. Best-effort background hygiene —
    /// failures are logged under `clipboard`, never presented.
    let clipboardWatchdog = ClipboardWatchdogCoordinator()

    /// The normalized failure currently presented by the standard report sheet.
    /// When a new failure arrives while one is presented, it supersedes the
    /// prior one (no queue in v1): the sheet always shows the most recent
    /// failure, and superseded/dismissed errors remain diagnosable in unified
    /// logging (`errorReporting` category).
    @Published var activeError: TartOperationError?

    /// Presents a normalized failure and records it in unified logging:
    /// operation, exit code, first stderr line, and hint. The raw stderr is
    /// not logged here — only the message line — keeping the log light while
    /// still diagnosing dismissed or superseded reports.
    func present(_ error: TartOperationError) {
        activeError = error
        // One assembled line: a long interpolated logger call exceeds the
        // Swift 5 mode type checker's budget. All parts are public by design.
        let exitCodeText = error.exitCode.map(String.init) ?? "-"
        let hintText = error.hint ?? "none"
        let line = "operation failed: \(error.operation) "
            + "exitCode=\(exitCodeText) message=\(error.message) hint=\(hintText)"
        Logger.errorReporting.error("\(line, privacy: .public)")
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: Jobs and creation (Issue 9)

    /// The long-running job surface. `@Published` so views reading
    /// `model.jobManager.jobs` re-render on every job mutation, and
    /// `VMListView` additionally observes it directly (finding 1).
    @Published private(set) var jobManager = JobManager()

    /// Cached free-bytes probe of the storage volume, refreshed on
    /// availability changes and every successful inventory fetch — never
    /// per view body evaluation (finding 14).
    @Published private(set) var storageFreeBytes: Int64?

    // MARK: - Clone flow (thin plumbing over tested TartKit surfaces)

    /// Guarded clone orchestration (validation + shared job body) — all
    /// decisions are tested in TartKit; this model only composes inputs.
    let cloneCoordinator = CloneCoordinator()

    /// Target of the Clone dialog (set from VMRowView's context menu;
    /// presentation lives in VMListView's item-driven sheet).
    @Published var cloningSource: VMEntry?

    /// Names the dialogs and the clone guard treat as unavailable: current
    /// inventory names plus in-flight job targets, so the inline feedback and
    /// the manager's duplicate-target guard can never disagree.
    func takenNames() -> Set<String> {
        var taken = Set((inventoryService.inventory?.localVMs.map(\.name) ?? [])
            + (inventoryService.inventory?.ociImages.map(\.name) ?? []))
        taken.formUnion(jobManager.activeTargets)
        return taken
    }

    /// True when the name is syntactically valid and free — inventory and
    /// in-flight job targets both count. Thin wrapper over the tested
    /// `CloneGuard` validator.
    func isNameAvailable(_ name: String) -> Bool {
        CloneGuard.validateName(name, taken: takenNames()) == nil
    }

    /// User-facing reason a name is unusable, shared by the create and clone
    /// dialogs (finding 7); nil while empty so no label flashes before typing.
    func nameIssue(_ name: String) -> String? {
        if name.isEmpty { return nil }
        switch CloneGuard.validateName(name, taken: takenNames()) {
        case nil, .empty:
            return nil
        case .invalidSyntax:
            return "Invalid name — no “/”, no “..”, and it must not start with “-”."
        case .taken:
            return "A VM or image with this name already exists."
        }
    }

    /// Why creation cannot start, or nil when it can. The create sheet
    /// disables its button and renders this text inline — never a silent
    /// no-op (finding 4). The in-flight-target check precedes the tart
    /// checks so the duplicate refusal fires even on a machine with no
    /// usable tart (the appended test requires it).
    func createBlockReason(name: String, reference: String) -> String? {
        if !VMNameRules.isValid(name) {
            return "The name may contain only letters, digits, dots, dashes, "
                + "and underscores, and must not start with “-”."
        }
        if !ImageReferenceRules.isValid(reference) {
            return "The image reference is not valid."
        }
        if jobManager.runningTargets.contains(name) {
            return "Another operation for “\(name)” is already running."
        }
        guard makeTartClient() != nil else {
            return "tart is missing, outdated, or no storage location is configured."
        }
        guard storageAvailability.isAvailable else {
            return "VM storage is unavailable — the volume is not mounted."
        }
        if !isNameAvailable(name) {
            return "A VM or image with this name already exists."
        }
        return nil
    }

    /// Starts the remote-image clone job (the create-from-image flow), now
    /// running the shared `JobManager.startClone` body (finding 4) — the
    /// inline clone body is gone; create and local clone share one. Returns
    /// nil when the job started and a user-facing reason otherwise — the
    /// create sheet shows the reason inline and stays open.
    @discardableResult
    func startCreate(name: String, reference: String) -> String? {
        if let reason = createBlockReason(name: name, reference: reference) {
            return reason
        }
        guard let client = makeTartClient() else {
            return "tart is unavailable."
        }
        if jobManager.startClone(source: reference, to: name, using: client) == nil {
            return "Another operation for “\(name)” is already running."
        }
        return nil
    }

    /// Starts a local clone. Thin plumbing: `CloneCoordinator` owns the
    /// guards and the shared job body; failure presentation and the
    /// inventory refresh run through `jobManager.onStateChange` (Issue 9).
    func startLocalClone(source: VMEntry, newName: String) {
        guard let client = makeTartClient() else { return }
        // Re-validate against the freshest row: the dialog's snapshot can go
        // stale while open (the VM may have been started externally).
        let current = inventoryService.inventory?.localVMs
            .first { $0.name == source.name } ?? source
        switch cloneCoordinator.start(source: current, newName: newName,
                                      taken: takenNames(), using: client,
                                      jobManager: jobManager) {
        case .started:
            break
        case .refused:
            break // the coordinator logged the reason
        }
    }

    /// Re-probes the storage volume's free space (cheap resource query).
    /// Called on availability changes and every successful fetch; views
    /// never probe per body evaluation (finding 14).
    private func refreshStorageFreeBytes() {
        if case .available(let path) = storageAvailability {
            storageFreeBytes = DiskSpace.freeBytes(atPath: path)
        } else {
            storageFreeBytes = nil
        }
    }

    // MARK: - Disk-space pre-check (shared by the create and clone dialogs)

    /// One filesystem probe per dialog presentation (finding 8): free space
    /// changes slowly and `DiskSpace.freeBytes` is a syscall, so the dialogs
    /// must not re-probe on every keystroke/render. Backed by the published
    /// `storageFreeBytes` probe (Issue 9) — refreshed on availability changes
    /// and every successful inventory fetch — instead of a second private
    /// cache, so exactly one probe mechanism exists.
    func freeBytesNow() -> Int64? {
        storageFreeBytes
    }

    /// Re-probes once; each dialog calls this on appear so the value is
    /// fresh exactly once per presentation.
    func invalidateStorageProbeCache() {
        refreshStorageFreeBytes()
    }

    /// Shared "Free space in storage" formatting (finding 7).
    var formattedFreeBytes: String {
        guard let free = freeBytesNow() else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    /// Clone pre-check decision — the estimate + verdict logic lives in the
    /// tested `DiskSpacePolicy` (finding 3), not in the view.
    func cloneSpaceVerdict(for source: VMEntry) -> DiskSpacePolicy.Verdict? {
        DiskSpacePolicy.localCloneVerdict(freeBytes: freeBytesNow(), source: source)
    }

    /// Create pre-check decision — same probe, the remote-image estimate
    /// (finding 7: CreateVMView shares this instead of its own copy).
    func createSpaceVerdict() -> DiskSpacePolicy.Verdict? {
        guard let free = freeBytesNow(), free > 0 else { return nil }
        return DiskSpacePolicy.verdict(freeBytes: free,
                                       estimatedNeedBytes: DiskSpacePolicy.remoteImageEstimateBytes)
    }

    // MARK: - Import flow (archive ingestion)

    /// Import pre-flight space assessment, computed here (policy + probes);
    /// the sheet renders it and makes no arithmetic of its own.
    struct ImportSpaceAssessment {
        let freeBytes: Int64?
        let estimateBytes: Int64?
        let verdict: DiskSpacePolicy.Verdict?

        /// The one decision the view renders. Unknowns (nil archive size or
        /// free space) conservatively ask for confirmation, so a refusal to
        /// proceed is never silent.
        var needsConfirmation: Bool { verdict.map(\.isTight) ?? true }
    }

    func importPreflight(path: String) -> ImportSpaceAssessment {
        guard case .available(let storagePath) = storageAvailability else {
            return ImportSpaceAssessment(freeBytes: nil, estimateBytes: nil, verdict: nil)
        }
        let free = DiskSpace.freeBytes(atPath: storagePath)
        let size = DiskSpace.fileSizeBytes(atPath: path)
        let verdict = size.flatMap { size in
            free.flatMap { DiskSpacePolicy.importVerdict(archiveFileSizeBytes: size, freeBytes: $0) }
        }
        return ImportSpaceAssessment(
            freeBytes: free,
            estimateBytes: size.map { DiskSpacePolicy.importEstimate(archiveFileSizeBytes: $0) },
            verdict: verdict)
    }

    /// True when an import may start right now: client available, storage
    /// available, and the name free in inventory AND among in-flight targets.
    func canImport(name: String) -> Bool {
        guard makeTartClient() != nil else { return false }
        if case .unavailable = storageAvailability { return false }
        return isNameAvailable(name)
    }

    /// Starts the import job. Every refusal is logged and presented through
    /// the standard sheet — no silent no-ops (finding 9).
    @discardableResult
    func startImport(path: String, name: String) -> JobInfo? {
        guard canImport(name: name) else {
            let line = "startImport refused for \(name): tart, storage, or a free name is missing"
            Logger.importJob.error("\(line, privacy: .public)")
            present(TartOperationError(
                operation: "import",
                message: "Import cannot start — tart is unavailable, storage is unavailable, "
                         + "or the name is taken.",
                rawDetails: ""))
            return nil
        }
        guard let client = makeTartClient() else { return nil }

        let kind = JobInfo.Kind.importArchive(name: name, path: path)
        let startedAt = Date()
        let job = ImportJob(
            name: name,
            path: path,
            startedAt: startedAt,
            ops: ImportJob.Ops(
                list: { try client.list() },
                importArchive: { path, name, onOutput, register in
                    try client.importArchive(at: path, to: name,
                                             onOutput: onOutput,
                                             registerCancel: register)
                },
                delete: { target in try client.delete(name: target) }),
            onCleanupAnomaly: { [weak self] failure in
                let analyzed = TartErrorAnalyzer.analyze(failure)
                Task { @MainActor in self?.present(analyzed) }
            })

        switch jobManager.start(kind: kind, body: { context in
            try job.run(context: context)
        }) {
        case .started(let info):
            return info
        case .duplicateTarget:
            let line = "startImport refused: \(name) already has a running job"
            Logger.importJob.error("\(line, privacy: .public)")
            present(TartOperationError(
                operation: "import",
                message: "An import for '\(name)' is already running.",
                rawDetails: ""))
            return nil
        }
    }

    // MARK: - Create from IPSW

    /// The IPSW create sheet's Space assessment: free bytes, the estimated
    /// need (DiskSpacePolicy), and the verdict. The view renders this and
    /// performs no arithmetic of its own.
    struct CreateIPSWSpaceAssessment {
        let freeBytes: Int64?
        let estimateBytes: Int64?
        let verdict: DiskSpacePolicy.Verdict?
    }

    func createIPSWPreflight(usesLatest: Bool, ipswPath: String,
                             diskSizeText: String) -> CreateIPSWSpaceAssessment {
        let diskSizeGB = IPSWCreateRules.parseDiskSizeGB(diskSizeText)
        guard case .available(let storagePath) = storageAvailability,
              let diskSizeGB else {
            // Unavailable storage or an invalid disk size: no estimate and no
            // gate — the sheet's inline error covers it.
            return CreateIPSWSpaceAssessment(freeBytes: nil, estimateBytes: nil, verdict: nil)
        }
        let free = DiskSpace.freeBytes(atPath: storagePath)
        // The local-file probe runs only in local mode: with "latest"
        // toggled, a previously picked path is never consulted.
        let fileSize = usesLatest ? nil : DiskSpace.fileSizeBytes(atPath: ipswPath)
        let estimate = DiskSpacePolicy.ipswEstimateBytes(
            usesLatest: usesLatest, ipswFileSizeBytes: fileSize, diskSizeGB: diskSizeGB)
        let verdict = DiskSpacePolicy.ipswVerdict(
            usesLatest: usesLatest, ipswFileSizeBytes: fileSize,
            diskSizeGB: diskSizeGB, freeBytes: free)
        return CreateIPSWSpaceAssessment(freeBytes: free, estimateBytes: estimate,
                                         verdict: verdict)
    }

    /// Why the IPSW create cannot start right now, for the sheet's inline
    /// error. Mirrors the image-create block reason.
    func createFromIPSWBlockReason(name: String, diskSizeGB: Int) -> String? {
        if makeTartClient() == nil {
            return "Install tart (see banner) to create a VM."
        }
        if case .unavailable = storageAvailability {
            return "VM storage is unavailable — creation cannot start."
        }
        if !isNameAvailable(name) {
            return "A VM, image, or running job with this name already exists."
        }
        if !(1...IPSWCreateRules.maxDiskSizeGB).contains(diskSizeGB) {
            return "Enter a whole number of gigabytes between 1 and \(IPSWCreateRules.maxDiskSizeGB)."
        }
        return nil
    }

    /// Starts the create-from-IPSW job. The body, pre-validation, and cleanup
    /// live in the tested `CreateFromIPSWJob` TartKit unit; this method is
    /// thin plumbing. Refusals are logged and presented through the standard
    /// sheet — never silent.
    @discardableResult
    func startCreateFromIPSW(name: String, ipsw: String, diskSizeGB: Int) -> JobInfo? {
        if let reason = createFromIPSWBlockReason(name: name, diskSizeGB: diskSizeGB) {
            Logger.createJob.error("startCreateFromIPSW refused for \(name, privacy: .public): \(reason, privacy: .public)")
            present(TartOperationError(operation: "create", message: reason, rawDetails: ""))
            return nil
        }
        guard let client = makeTartClient() else { return nil }

        let kind = JobInfo.Kind.createFromIPSW(name: name)
        let startedAt = Date()
        let job = CreateFromIPSWJob(
            name: name,
            ipsw: ipsw,
            diskSizeGB: diskSizeGB,
            startedAt: startedAt,
            ops: CreateFromIPSWJob.Ops(
                list: { try client.list() },
                createFromIPSW: { name, ipsw, gb, onOutput, register in
                    try client.createFromIPSW(name: name, ipsw: ipsw, diskSizeGB: gb,
                                              onOutput: onOutput, registerCancel: register)
                },
                delete: { target in try client.delete(name: target) }),
            onCleanupAnomaly: { [weak self] failure in
                let analyzed = TartErrorAnalyzer.analyze(failure)
                Task { @MainActor in self?.present(analyzed) }
            })

        switch jobManager.start(kind: kind, body: { context in
            try job.run(context: context)
        }) {
        case .started(let info):
            return info
        case .duplicateTarget:
            Logger.createJob.error("startCreateFromIPSW refused: \(name, privacy: .public) already has a running job")
            present(TartOperationError(
                operation: "create",
                message: "A creation for '\(name)' is already running.",
                rawDetails: ""))
            return nil
        }
    }

    /// Runs a local, stopped VM as a detached process. Thin plumbing:
    /// `RunCoordinator` owns the race-safe guard, registry, eviction, and
    /// failure text (tested in TartKit); this method only guards what the
    /// UI cannot express and wires the outcome to the standard report.
    func run(vm: VMEntry) async {
        guard vm.isLocal, !vm.running else { return }
        guard let client = makeTartClient() else { return }
        // Read the saved share list once per launch, synchronously, before
        // the launch call: mid-run edits cannot affect an already-started
        // process — they apply at the next run, exactly as the UI hint
        // promises. `requestRun` (Issue 13) and resume (Issue 12) funnel
        // through this method and inherit shares unchanged.
        let shares = settings.sharedFolders(for: vm.name)
        switch await runCoordinator.launch(name: vm.name, using: client, shares: shares) {
        case .started:
            // Coalesced refresh: skipped when a poll just completed; the
            // poll (≤3 s) is the reconciler of record for the new state.
            await inventoryService.refreshIfStale()
            // Clipboard hygiene for darwin guests: kick the guest agent and
            // (re)install its watchdog. Fire-and-forget background work —
            // it must never block or fail the run (degrades are logged).
            Task { await clipboardWatchdog.ensureInstalled(name: vm.name, client: client) }
        case .alreadyLaunching:
            break // a fast double-click raced; the first launch is authoritative
        case .failed(_, _, let cause):
            present(cause.normalized)
        }
    }

    // MARK: Memory over-commitment warning (soft guardrail)

    /// Pending over-commitment confirmation. The VM and its assessment are
    /// one unit, set and cleared together — a single optional instead of
    /// two lockstep values.
    struct PendingRunWarning {
        let vm: VMEntry
        let assessment: MemoryOvercommitPolicy.Assessment
    }

    @Published var pendingRunWarning: PendingRunWarning?

    /// The VM whose first-run reminder is currently presented. A VM created
    /// from an IPSW that has never been observed running gets the one-time
    /// Setup Assistant reminder before the actual launch.
    @Published var firstRunVM: VMEntry?

    /// Run entry point for the list rows: a flagged IPSW-created VM presents
    /// the one-time Setup Assistant reminder before the actual launch; every
    /// other VM proceeds straight to the memory over-commitment assessment.
    func requestRun(vm: VMEntry) async {
        guard vm.isLocal, !vm.running else { return }
        if firstRunReminder.contains(vm.name) {
            firstRunVM = vm
            return
        }
        await assessMemoryAndRun(vm: vm)
    }

    /// The reminder was acknowledged: proceed with the run, through the same
    /// memory assessment as any other run. The flag itself is cleared later,
    /// when the inventory first reports the VM running, so a cancelled dialog
    /// or a failed run keeps reminding.
    func confirmFirstRun() {
        guard let vm = firstRunVM else { return }
        firstRunVM = nil
        Task { await self.assessMemoryAndRun(vm: vm) }
    }

    /// The shared run path after the first-run gate: assesses the combined
    /// allocation against host RAM and warns (non-blocking) when the shared
    /// fraction is reached. A suspended VM is assessed as the target — the
    /// same arithmetic as a cold start. Every outcome, including every
    /// degrade path, is logged so an unavailable guardrail is
    /// distinguishable from "no warning needed".
    private func assessMemoryAndRun(vm: VMEntry) async {
        guard let client = makeTartClient() else {
            Logger.overcommit.warning(
                "tart unavailable; running \(vm.name, privacy: .public) without a memory assessment")
            await run(vm: vm)
            return
        }
        guard let snapshot = await inventoryService.memoryAllocationSnapshot(
            for: vm.name,
            getConfig: { name in try client.get(name: name) }) else {
            Logger.overcommit.warning(
                "no allocation snapshot for \(vm.name, privacy: .public); running without a warning")
            await run(vm: vm)
            return
        }
        let runningMB = snapshot.runningMB.reduce(0, +)
        switch MemoryOvercommitPolicy.decide(runningMemoryMB: runningMB,
                                              targetMemoryMB: snapshot.targetMB,
                                              host: .current()) {
        case .proceed:
            Logger.overcommit.info(
                "running \(vm.name, privacy: .public): running VMs \(runningMB) MB + target \(snapshot.targetMB) MB stay below \(HostMemoryWarnings.warningFraction) of host RAM")
            await run(vm: vm)
        case .warn(let assessment):
            Logger.overcommit.info(
                "warning on \(vm.name, privacy: .public): \(assessment.summaryText, privacy: .public)")
            pendingRunWarning = PendingRunWarning(vm: vm, assessment: assessment)
        }
    }

    /// The user confirmed the over-commitment warning: run anyway.
    /// The pending unit is captured synchronously, before any suspension:
    /// the dialog's presentation binding clears `pendingRunWarning` on
    /// dismissal, so an action that only reads the pending state after an
    /// `await` would observe nil and silently no-op (Run Anyway would
    /// never run the VM).
    func proceedWithWarningRun() {
        guard let pending = pendingRunWarning else { return }
        pendingRunWarning = nil
        let vm = pending.vm
        Task { await self.run(vm: vm) }
    }

    func cancelWarningRun() {
        pendingRunWarning = nil
    }

    let stopCoordinator = StopCoordinator()

    /// Target of the Force Stop confirmation dialog.
    @Published var pendingForceStop: VMEntry?

    // MARK: Detail pane

    /// The selected list row (drives the detail pane).
    @Published var selectedVM: VMEntry?
    /// Details of the selection; refreshed on selection and inventory changes.
    @Published private(set) var selectedDetails: VMDetails?
    /// Mirror of the inventory service's snapshot. SwiftUI views observe only
    /// AppModel (via @EnvironmentObject), so the detail refresh must be
    /// triggered from a published property of this class — not from
    /// `inventoryService.inventory`, which no view observes.
    @Published private(set) var inventory: VMInventory?

    private var cachedConfig: (name: String, config: VMConfigInfo)?
    private var detailGeneration = 0
    private var inventoryObserver: AnyCancellable?

    /// Stops a running VM (graceful by default; `force` terminates
    /// immediately). Thin plumbing: `StopCoordinator` owns the pre-checks,
    /// single-flight guard, off-main-actor command, reconciliation, and
    /// logging (tested in TartKit); this method only wires the outcome to
    /// the standard report. Only a confirmed still-running VM presents the
    /// sheet — reconciled and unknown outcomes stay silent by design.
    /// No explicit run-registry cleanup is needed: the next poll reports the
    /// VM stopped and the app's `$inventory` sink evicts the run handle.
    func stop(vm: VMEntry, force: Bool = false) async {
        guard let client = makeTartClient() else { return }
        switch await stopCoordinator.stop(vm: vm, force: force,
                                          using: client, inventory: inventoryService) {
        case .stopped, .reconciled:
            // Coalesced refresh: skipped when a poll just completed; the
            // poll (≤3 s) is the reconciler of record for the new state.
            await inventoryService.refreshIfStale()
        case .stillRunning(_, _, let cause):
            present(cause.normalized)
        case .unknown:
            break // coordinator logged it; no false error on unknown state
        case .alreadyStopping, .notStoppable:
            break
        }
    }

    let suspendCoordinator = SuspendCoordinator()

    /// Suspends a running VM. Thin plumbing: `SuspendCoordinator` owns the
    /// pre-checks, single-flight guard, off-main-actor command, failure
    /// normalization, reconciliation, and logging (tested in TartKit); this
    /// method only wires the outcome and the registry release.
    func suspend(vm: VMEntry) async {
        guard let client = makeTartClient() else { return }
        switch await suspendCoordinator.suspend(vm: vm, using: client,
                                                inventory: inventoryService) {
        case .suspended, .reconciled:
            // The VM left the running state: its run handle is stale.
            // Release it deterministically so a Resume click is never
            // blocked by the registry while waiting for the next poll's
            // reconcile eviction (review finding 1).
            runCoordinator.release(name: vm.name)
            Logger.suspend.info(
                "released stale run handle for '\(vm.name, privacy: .public)' after suspend")
            // Coalesced refresh (Issue 4): the poll (≤3 s) is the reconciler
            // of record; skip when one just completed.
            await inventoryService.refreshIfStale()
            await refreshSelectedDetails()
        case .stillRunning(_, let error):
            present(error) // the coordinator already refreshed to confirm
        case .unknown, .alreadySuspending, .notSuspendable:
            break // coordinator logged each; no false error on unknown state
        }
    }

    // MARK: Resource editing

    /// True while a `tart set`-family operation is in flight (disables the editor).
    @Published private(set) var applyingResources = false

    /// Applies a resource draft to a stopped VM.
    /// Defense in depth: re-resolves the row from the current inventory,
    /// re-checks the editability gate, and re-runs the same pure validator
    /// before any CLI call; tart is the final authority. A validation
    /// rejection is logged AND surfaced through the standard sheet — never
    /// a silent return.
    func apply(fields: ResourceEditorFields, to entry: VMEntry,
               host: HostFacts = .current()) async {
        let update = fields.update
        guard !update.isEmpty else {
            Logger.resources.info("apply skipped: empty update for \(entry.name, privacy: .public)")
            return
        }
        let current = inventoryService.inventory?.localVMs
            .first { $0.name == entry.name } ?? entry
        guard current.canEditResources else {
            Logger.resources.warning(
                "apply blocked: \(current.name, privacy: .public) is \(current.state, privacy: .public)")
            return
        }
        let validation = VMResourceValidator.validate(fields: fields,
                                                      currentDiskGB: current.diskSize,
                                                      host: host)
        guard validation.isValid else {
            let message = validation.errors.joined(separator: " ")
            Logger.resources.error(
                "apply rejected for \(current.name, privacy: .public): \(message, privacy: .public)")
            present(TartOperationError(
                operation: "set",
                message: "The change to \(current.name) was not applied: \(message)",
                rawDetails: validation.errors.joined(separator: "\n")))
            return
        }
        let succeeded = await runSetOperation(current, operation: "set") { client in
            try client.set(name: current.name, update: update)
        }
        if succeeded, let displayRefit = update.displayRefit {
            settings.setDisplayRefitPreference(displayRefit, for: current.name)
        }
    }

    /// Regenerates the MAC address of a stopped VM.
    func regenerateMAC(for entry: VMEntry) async {
        _ = await runSetOperation(entry, operation: "set --random-mac") { client in
            try client.regenerateMAC(name: entry.name)
        }
    }

    /// Regenerates the serial number of a stopped VM.
    func regenerateSerial(for entry: VMEntry) async {
        _ = await runSetOperation(entry, operation: "set --random-serial") { client in
            try client.regenerateSerial(name: entry.name)
        }
    }

    /// Shared wrapper for `tart set`-family operations: client-availability
    /// and editability guards, in-flight state, logging, error presentation,
    /// and detail+inventory refresh on success (always).
    private func runSetOperation(_ entry: VMEntry,
                                 operation: String,
                                 _ operationBody: @escaping @Sendable (TartClient) throws -> Void) async -> Bool {
        guard entry.canEditResources else {
            Logger.resources.warning(
                "\(operation, privacy: .public) blocked: \(entry.name, privacy: .public) is \(entry.state, privacy: .public)")
            return false
        }
        let succeeded = await runForegroundOperation(
            operation,
            activity: \.applyingResources,
            logger: Logger.resources,
            subject: entry.name,
            operationBody)
        if succeeded {
            await refreshSelectedDetails()
            await inventoryService.refresh()
        }
        return succeeded
    }

    // MARK: Shared foreground-operation wrapper (used by resource editing too)

    /// The single foreground-run boilerplate: client-availability guard,
    /// in-flight state, detached execution, normalization (with an optional
    /// redactor), logging, and the standard sheet. `runSetOperation` and both
    /// registry operations route through it — parameterized by the command
    /// label and the in-flight key path.
    @discardableResult
    private func runForegroundOperation(
        _ commandLabel: String,
        activity: ReferenceWritableKeyPath<AppModel, Bool>,
        logger: Logger,
        subject: String? = nil,
        redact: @escaping @Sendable (String) -> String = { $0 },
        _ body: @escaping @Sendable (TartClient) throws -> Void
    ) async -> Bool {
        guard !self[keyPath: activity] else {
            logger.notice("\(commandLabel, privacy: .public) skipped — an operation is already in flight")
            return false
        }
        guard let client = makeTartClient() else {
            // tart unavailable (missing/outdated binary, or storage
            // unconfigured): the UI disables the buttons, and this line is
            // the diagnosable trace if a call ever slips through.
            logger.error("\(commandLabel, privacy: .public) aborted — tart is unavailable")
            return false
        }
        setActivity(true, at: activity)
        defer { setActivity(false, at: activity) }
        let who = subject.map { " for \($0)" } ?? ""
        logger.info("\(commandLabel, privacy: .public) starting\(who, privacy: .public)")
        let outcome = await Task.detached(priority: .userInitiated) { () -> TartOperationError? in
            do {
                try body(client)
                return nil
            } catch let error as TartClientError {
                // The choke point, in its redacting form: secrets are
                // scrubbed before the sheet, clipboard, or log see the
                // failure text.
                return error.normalized(redact: redact)
            } catch let error as RegistryArgumentError {
                return error.normalized
            } catch {
                return TartClientError.commandFailed(command: commandLabel, exitCode: -1,
                                                     stdout: "", stderr: "\(error)")
                    .normalized(redact: redact)
            }
        }.value
        if let failure = outcome {
            logger.error("\(commandLabel, privacy: .public) failed\(who, privacy: .public): \(failure.message, privacy: .public)")
            present(failure)
            return false
        }
        logger.info("\(commandLabel, privacy: .public) succeeded\(who, privacy: .public)")
        return true
    }

    /// Synchronous key-path setter for the in-flight flags: assigning
    /// `self[keyPath:]` directly inside an async method is rejected (the
    /// async lowering makes `self` immutable), so the mutation happens in
    /// this non-async helper.
    private func setActivity(_ value: Bool, at keyPath: ReferenceWritableKeyPath<AppModel, Bool>) {
        self[keyPath: keyPath] = value
    }

    // MARK: Registries

    /// True while a registry operation is in flight; the Registries section
    /// disables both buttons while set.
    @Published private(set) var registryOperationInFlight = false

    /// Signs in to a registry. host and username are logged (never the
    /// password); the password is held only by the operation body and its
    /// redactor, both of which go out of scope when this function returns.
    @discardableResult
    func registryLogin(host: String, username: String, password: String) async -> Bool {
        await runForegroundOperation(
            "login",
            activity: \.registryOperationInFlight,
            logger: Logger.registries,
            subject: "\(host) as \(username)",
            redact: RegistryCredentialScrubber.redactor(secret: password)) { client in
                try client.login(host: host, username: username, password: password)
            }
    }

    /// Signs out of a registry (removes tart's stored credentials for the
    /// host). Logout output carries no credentials, so the redactor stays
    /// the identity pass-through.
    @discardableResult
    func registryLogout(host: String) async -> Bool {
        await runForegroundOperation(
            "logout",
            activity: \.registryOperationInFlight,
            logger: Logger.registries,
            subject: host) { client in
                try client.logout(host: host)
            }
    }

    // MARK: Snapshots (Issue 14)

    /// Snapshots of the currently selected VM (refreshed with details).
    @Published private(set) var vmSnapshots: [Snapshot] = []

    /// The resolved snapshots folder, or nil when no storage is configured
    /// (mid-onboarding — no temp fallback, finding 8).
    var resolvedSnapshotsFolder: String? {
        SnapshotService.resolveDirectory(storagePath: settings.storagePath,
                                         configuredFolder: settings.snapshotsFolder)
    }

    /// One memoizing store per resolved folder (finding 6): reusing the same
    /// instance across poll cycles lets the fingerprint cache pay off.
    private var snapshotStoreCache: (directory: String, store: SnapshotStore)?

    var snapshotStore: SnapshotStore? {
        guard let directory = resolvedSnapshotsFolder else { return nil }
        if let cached = snapshotStoreCache, cached.directory == directory {
            return cached.store
        }
        let store = SnapshotStore(directory: directory)
        snapshotStoreCache = (directory, store)
        return store
    }

    /// The export pre-flight, probed on the SNAPSHOTS FOLDER's volume — the
    /// destination of the write — never the VM-storage volume (finding 3).
    struct SnapshotSpaceAssessment {
        let freeBytes: Int64?
        let estimateBytes: Int64?
        let verdict: DiskSpacePolicy.Verdict?
    }

    func snapshotSpaceAssessment(vm: VMEntry) -> SnapshotSpaceAssessment {
        guard let directory = resolvedSnapshotsFolder else {
            return SnapshotSpaceAssessment(freeBytes: nil,
                                           estimateBytes: DiskSpacePolicy.exportEstimate(
                                               vmDiskUsageGB: vm.diskUsage),
                                           verdict: nil)
        }
        let free = DiskSpace.freeBytes(forDestination: directory)
        let estimate = DiskSpacePolicy.exportEstimate(vmDiskUsageGB: vm.diskUsage)
        let verdict = free.flatMap {
            DiskSpacePolicy.exportVerdict(vmDiskUsageGB: vm.diskUsage, freeBytes: $0)
        }
        return SnapshotSpaceAssessment(freeBytes: free, estimateBytes: estimate, verdict: verdict)
    }

    /// Snapshots require a stopped VM with storage configured, tart
    /// available, and no other in-flight job for the VM; drives the sheet's
    /// button state (finding 8's gate).
    func checkSnapshotPossible(vm: VMEntry) -> Bool {
        vm.isLocal && !vm.running
            && makeTartClient() != nil
            && resolvedSnapshotsFolder != nil
            && !jobManager.runningTargets.contains(vm.name)
    }

    /// Creates a snapshot of a stopped VM as an export job. Thin plumbing
    /// (finding 4): all pipeline logic lives in the tested `SnapshotCreateJob`.
    func createSnapshot(vm: VMEntry, label: String?) {
        guard vm.isLocal, !vm.running else { return }
        guard let client = makeTartClient() else { return }
        guard let directory = resolvedSnapshotsFolder else {
            let refusalLine = "snapshot refused for \(vm.name): no storage configured "
                + "(no snapshots folder)"
            Logger.snapshot.error("\(refusalLine, privacy: .public)")
            present(TartOperationError(
                operation: "snapshot",
                message: "Choose VM storage first — a snapshots folder cannot be resolved yet.",
                rawDetails: ""))
            return
        }
        let store = snapshotStore ?? SnapshotStore(directory: directory)
        let vmName = vm.name
        let createdAt = Date()
        let archivePath = store.proposeArchivePath(vmName: vmName, label: label, date: createdAt)

        let job = SnapshotCreateJob(
            vmName: vmName, label: label, archivePath: archivePath,
            createdAt: createdAt, directory: directory, store: store,
            ops: SnapshotCreateJob.Ops(
                ensureDirectory: { path in
                    try FileManager.default.createDirectory(atPath: path,
                                                            withIntermediateDirectories: true)
                },
                list: { try client.list() },
                export: { name, path, onOutput, register in
                    try client.export(name: name, to: path,
                                      onOutput: onOutput, registerCancel: register)
                }))

        switch jobManager.start(kind: .exportSnapshot(vm: vmName), body: { context in
            try job.run(context: context)
        }) {
        case .started:
            break
        case .duplicateTarget(let target):
            let refusalLine = "snapshot refused: \(target) already has a running job"
            Logger.snapshot.error("\(refusalLine, privacy: .public)")
            present(TartOperationError(
                operation: "snapshot",
                message: "Another operation for “\(target)” is already running.",
                rawDetails: ""))
        }
    }

    // MARK: Snapshot restore and delete

    struct PendingSnapshotRestore: Identifiable, Equatable {
        let vm: VMEntry
        let snapshot: Snapshot
        var id: String { snapshot.id }
    }

    /// Target of the restore sheet (typed-name gate + safety toggle).
    @Published var pendingRestore: PendingSnapshotRestore?

    /// Gates the Restore affordance: a stopped local VM with tart available,
    /// the snapshots folder resolvable, and no in-flight job for the VM. The
    /// button is disabled instead of clicking into a silent refusal.
    func checkRestorePossible(vm: VMEntry) -> Bool {
        vm.isLocal && !vm.running
            && makeTartClient() != nil
            && snapshotStore != nil
            && !jobManager.runningTargets.contains(vm.name)
    }

    /// Restores a VM from a snapshot archive via the atomic pipeline. Thin
    /// plumbing: `SnapshotRestoreJob` (TartKit) owns the pre-flight, per-stage
    /// progress, race tolerances, safety sidecar, bounded output capture,
    /// guidance text, and logging. Every refusal here is presented — never
    /// silent.
    func restore(snapshot: Snapshot, vm: VMEntry, useSafety: Bool) {
        guard vm.isLocal, !vm.running else {
            let refusalLine = "restore refused for \(vm.name): not a stopped local VM"
            Logger.restore.error("\(refusalLine, privacy: .public)")
            return
        }
        guard let client = makeTartClient() else {
            Logger.restore.error("restore refused: tart unavailable")
            present(TartOperationError(
                operation: "restore",
                message: "Restore cannot start — tart is unavailable. "
                    + "Install or locate tart first.",
                rawDetails: ""))
            return
        }
        guard let store = snapshotStore, let storagePath = settings.storagePath else {
            Logger.restore.error("restore refused: no snapshots folder resolvable (no VM storage configured)")
            present(TartOperationError(
                operation: "restore",
                message: "Restore cannot start — choose VM storage first so the "
                    + "snapshots folder can be resolved.",
                rawDetails: ""))
            return
        }

        let vmName = vm.name
        let archivePath = snapshot.archivePath
        let createdAt = Date()
        let safetyPath = useSafety
            ? store.proposeArchivePath(vmName: vmName, label: "safety-before-restore",
                                       date: createdAt)
            : nil

        let job = SnapshotRestoreJob(
            vmName: vmName, archivePath: archivePath, safetyArchivePath: safetyPath,
            vmDiskUsageGB: vm.diskUsage, storagePath: storagePath,
            store: store, safetyCreatedAt: createdAt,
            ops: SnapshotRestoreJob.Ops(
                stop: { name in
                    // The single async→sync bridge: the job body blocks here
                    // like it blocks on `waitForExit`; bounded by
                    // `TartClient.stopCommandTimeout` (90 s).
                    let semaphore = DispatchSemaphore(value: 0)
                    let box = SyncResultBox()
                    Task.detached(priority: .userInitiated) {
                        do {
                            try await client.stop(name: name)
                            box.set(.success(()))
                        } catch {
                            box.set(.failure(error))
                        }
                        semaphore.signal()
                    }
                    semaphore.wait()
                    try (box.result ?? .failure(TartClientError.launchFailed(
                        command: "stop", executable: client.binaryPath))).get()
                },
                list: { try client.list() },
                export: { name, path, onOutput, register in
                    try client.export(name: name, to: path,
                                      onOutput: onOutput, registerCancel: register)
                },
                delete: { name in try client.delete(name: name) },
                importArchive: { path, name, onOutput, register in
                    try client.importArchive(at: path, to: name,
                                             onOutput: onOutput, registerCancel: register)
                },
                sourceStatus: { FileManager.default.isReadableFile(atPath: $0) },
                fileSize: { DiskSpace.fileSizeBytes(atPath: $0) },
                freeBytes: { path in
                    DiskSpace.freeBytes(atPath: path) ?? DiskSpace.freeBytes(forDestination: path)
                }))

        switch jobManager.start(kind: .restoreSnapshot(vm: vmName), body: { context in
            try job.run(context: context)
        }) {
        case .started:
            break
        case .duplicateTarget(let target):
            let refusalLine = "restore refused: \(target) already has a running job"
            Logger.restore.error("\(refusalLine, privacy: .public)")
            present(TartOperationError(
                operation: "restore",
                message: "Another operation for “\(target)” is already running.",
                rawDetails: ""))
        }
    }

    /// Deletes a snapshot archive after UI confirmation; the scan reconciles.
    /// `SnapshotStore.delete` removes the archive first (metadata preserved on
    /// failure) and invalidates the memo cache.
    func deleteSnapshot(_ snapshot: Snapshot) async {
        guard let store = snapshotStore else { return }
        do {
            try store.delete(snapshot)
        } catch {
            present(TartClientError.commandFailed(
                command: "snapshot-delete", exitCode: 1, stdout: "",
                stderr: "\(error)").normalized)
        }
        await refreshSelectedDetails()
    }

    func checkPrerequisite() {
        guard !isCheckingPrerequisite else { return }
        isCheckingPrerequisite = true
        // The checker runs synchronously; a wedged tart binary is bounded by
        // ProcessRunner's timeout, so the check goes off the main actor.
        let checker = self.checker
        Task { [weak self] in
            let status = await Task.detached(priority: .userInitiated) {
                checker.check()
            }.value
            guard let self else { return }
            self.prerequisite = status
            self.isCheckingPrerequisite = false
            self.rewireInventoryFetch()
        }
    }

    /// Re-probes the configured storage and logs transitions.
    func refreshAvailability() {
        let previous = storageAvailability
        let current = StorageLocationValidator.availability(at: settings.storagePath)
        guard current != previous else { return }
        storageAvailability = current
        refreshStorageFreeBytes()   // Issue 9: probe rides availability changes
        switch current {
        case .available(let path):
            Logger.storage.info("storage available at \(path, privacy: .public)")
        case .unavailable(let path, let reason):
            Logger.storage.warning(
                "storage unavailable at \(path, privacy: .public): \(reason.rawValue, privacy: .public)")
        }
    }

    /// The single gate for storage changes: validate once, then commit.
    /// `settings.storagePath` is therefore only ever a path that passed
    /// `StorageLocationValidator.validate` — no call-site discipline needed.
    @discardableResult
    func attemptChooseStorage(path: String) -> StorageValidation {
        let result = StorageLocationValidator.validate(path)
        switch result {
        case .valid(let validPath):
            settings.storagePath = validPath
            Logger.settings.info("storage path set to \(validPath, privacy: .public)")
            refreshAvailability()
            rewireInventoryFetch()
        case .invalid(let invalidPath, let reason):
            Logger.settings.info(
                "storage choice rejected: \(invalidPath, privacy: .public) — \(reason, privacy: .public)")
        }
        return result
    }

    /// Selection entry point for the list binding. Invalidating a selection
    /// clears its details, drops the config cache, and bumps the generation
    /// so any in-flight refresh can no longer publish a stale payload.
    func select(_ entry: VMEntry?) {
        if entry?.name != selectedVM?.name {
            cachedConfig = nil
            selectedDetails = nil
            vmSnapshots = []
            detailGeneration += 1
        }
        selectedVM = entry
        settings.selectedVMName = entry?.isLocal == true ? entry?.name : nil
    }

    /// Refreshes the detail pane for the current selection. Follows
    /// VMDetailsResolver.plan: config fetched once per selection (static in
    /// this slice) and cached; the IP rechecked only for running local VMs;
    /// OCI selections make no tart calls at all. Every publish site re-checks
    /// the generation and the selection name after each await, so a slower
    /// older fetch can never overwrite the current selection's details.
    func refreshSelectedDetails() async {
        guard let selected = selectedVM else { return }
        detailGeneration += 1
        let generation = detailGeneration
        let name = selected.name

        guard let client = makeTartClient() else {
            selectedDetails = VMDetailsResolver.assemble(
                entry: selected, config: nil, ip: nil, fetchedAt: Date())
            return
        }

        // The freshest row with this name (running state may have flipped).
        let inventory = inventoryService.inventory
        let entry = inventory?.localVMs.first { $0.name == name }
            ?? inventory?.ociImages.first { $0.name == name }
            ?? selected

        let plan = VMDetailsResolver.plan(for: entry,
                                          configIsCached: cachedConfig?.name == name)

        let config: VMConfigInfo?
        if plan.fetchConfig {
            config = try? await Task.detached(priority: .utility) {
                try client.get(name: name)
            }.value
            guard generation == detailGeneration, selectedVM?.name == name else { return }
            cachedConfig = config.map { (name: name, config: $0) }
        } else {
            config = cachedConfig?.name == name ? cachedConfig?.config : nil
        }
        guard generation == detailGeneration, selectedVM?.name == name else { return }

        let ip: String?
        if plan.fetchIP {
            ip = (try? await Task.detached(priority: .utility) {
                try client.ip(name: name)
            }.value) ?? nil
        } else {
            ip = nil
        }
        guard generation == detailGeneration, selectedVM?.name == name else { return }

        selectedDetails = VMDetailsResolver.assemble(
            entry: entry, config: config, ip: ip, fetchedAt: Date())

        // Issue 14: the per-VM snapshot list rides the same refresh cadence,
        // but the catalog scan runs OFF the main actor and is memoized per
        // poll cycle (finding 6).
        if let store = snapshotStore {
            let snapshots: [Snapshot]? = try? await Task.detached(priority: .utility) {
                try store.snapshots(forVM: name)
            }.value
            guard generation == detailGeneration, selectedVM?.name == name else { return }
            vmSnapshots = snapshots ?? []
        } else {
            vmSnapshots = []
        }
    }

    // MARK: Delete and rename (lifecycle)

    /// Target of the Rename sheet (owned by ContentView, Task 8).
    @Published var renamingSource: VMEntry?
    /// Target of the Delete confirmation sheet (owned by ContentView, Task 8).
    @Published var deletingSource: VMEntry?

    /// True when a delete could start right now: a stopped local VM with a
    /// usable tart and available storage (PRD Story 1 AC-6: actions disabled
    /// until storage resolves). The sheet disables its Delete button on this.
    func canDelete(vm: VMEntry) -> Bool {
        guard vm.isStoppedLocal else { return false }
        guard makeTartClient() != nil else { return false }
        if case .unavailable = storageAvailability { return false }
        return true
    }

    /// True when a rename could start right now: stopped local VM, free
    /// target name (inventory + in-flight job targets), tart + storage
    /// available.
    func canRename(vm: VMEntry, to name: String) -> Bool {
        guard vm.isStoppedLocal else { return false }
        guard !name.isEmpty, name != vm.name, isNameAvailable(name) else { return false }
        guard makeTartClient() != nil else { return false }
        if case .unavailable = storageAvailability { return false }
        return true
    }

    /// Deletes a stopped VM as an uncancellable job. The typed confirmation
    /// is re-verified at this boundary (finding 8) — the view's gate is UX,
    /// this is the model invariant. Every refusal is logged and presented
    /// through the standard sheet — no silent no-ops (finding 5). The job
    /// body calls only the injected ops, wired to TartClient.delete
    /// (finding 1): no argv or error construction exists in this layer.
    @discardableResult
    func startDelete(vm: VMEntry, confirmation: String) -> JobInfo? {
        guard TypedConfirmationGate.allowsProceed(typedName: confirmation, vmName: vm.name) else {
            Logger.deleteVM.error("delete refused for \(vm.name, privacy: .public): typed confirmation mismatch")
            present(TartOperationError(
                operation: "delete",
                message: "Delete refused — the typed name does not match the VM.",
                rawDetails: ""))
            return nil
        }
        guard vm.isStoppedLocal else {
            Logger.deleteVM.error("delete refused for \(vm.name, privacy: .public): not a stopped local VM")
            present(TartOperationError(
                operation: "delete",
                message: "“\(vm.name)” is not stopped — stop the VM before deleting it.",
                rawDetails: ""))
            return nil
        }
        guard canDelete(vm: vm) else {
            Logger.deleteVM.error("delete refused for \(vm.name, privacy: .public): tart or storage unavailable")
            present(TartOperationError(
                operation: "delete",
                message: "Delete cannot start — tart is unavailable or VM storage is not mounted.",
                rawDetails: ""))
            return nil
        }
        guard let client = makeTartClient() else { return nil }

        let job = VMDeleteJob(
            name: vm.name,
            ops: VMDeleteJob.Ops(
                list: { try client.list() },
                delete: { name, timeout in try client.delete(name: name, timeout: timeout) }))
        switch jobManager.start(kind: .deleteVM(name: vm.name), body: { context in
            try job.run(context: context)
        }) {
        case .started(let info):
            return info
        case .duplicateTarget:
            Logger.deleteVM.error("delete refused for \(vm.name, privacy: .public): a job already targets it")
            present(TartOperationError(
                operation: "delete",
                message: "A job for “\(vm.name)” is already running.",
                rawDetails: ""))
            return nil
        }
    }

    /// Renames a stopped VM. Inline collision validation is UX; the fresh-
    /// list pre-validation in VMRename is the guard, and tart is the final
    /// authority (its rejections surface through the standard sheet). Every
    /// refusal is logged and presented — no silent no-ops (finding 5).
    func rename(vm: VMEntry, to newName: String) async {
        guard vm.isStoppedLocal else {
            Logger.rename.error("rename refused for \(vm.name, privacy: .public): not a stopped local VM")
            present(TartOperationError(
                operation: "rename",
                message: "“\(vm.name)” is not stopped — stop the VM before renaming it.",
                rawDetails: ""))
            return
        }
        guard canRename(vm: vm, to: newName) else {
            Logger.rename.error("rename refused for \(vm.name, privacy: .public): unavailable client/storage or taken name")
            present(TartOperationError(
                operation: "rename",
                message: "Rename cannot start — tart or storage is unavailable, or the name is taken.",
                rawDetails: ""))
            return
        }
        guard let client = makeTartClient() else { return }

        let oldName = vm.name
        let ops = VMRename.Ops(
            list: { try client.list() },
            rename: { from, to in try client.rename(from: from, to: to) })
        let failure = await Task.detached(priority: .userInitiated) { () -> TartClientError? in
            do {
                _ = try VMRename.perform(from: oldName, to: newName, ops: ops)
                return nil
            } catch let error as TartClientError {
                return error
            } catch {
                return TartClientError.commandFailed(command: "rename", exitCode: -1,
                                                     stdout: "", stderr: String(describing: error))
            }
        }.value
        await inventoryService.refresh()
        await refreshSelectedDetails()
        if let failure {
            present(TartErrorAnalyzer.analyze(failure))
        }
    }

    // MARK: - Replace Disk (thin plumbing over tested TartKit surfaces)

    /// Target of the Replace Disk confirmation sheet.
    @Published var replacingDiskSource: VMEntry?

    /// Guarded replace-disk orchestration (validation + job start) — every
    /// decision is tested in TartKit; this model only composes inputs.
    let replaceDiskCoordinator = ReplaceDiskCoordinator()

    /// Confirms and starts the disk replacement.
    /// Defense in depth: the row is re-resolved from the live inventory at
    /// confirm time (Issue 8's apply pattern), so a VM that became running
    /// or suspended while the sheet was open is refused by the tested guard.
    /// Every refusal — the state race, a duplicate in-flight target, or a
    /// missing tart client — is logged AND presented through the standard
    /// sheet. No path returns silently (finding 5).
    func replaceDisk(vm: VMEntry, path: String, typedName: String) {
        let current = inventoryService.inventory?.localVMs
            .first { $0.name == vm.name } ?? vm
        guard let client = makeTartClient() else {
            Logger.replaceDisk.error(
                "replace disk: tart unavailable for \(current.name, privacy: .public)")
            present(TartOperationError(
                operation: "set",
                message: "tart is unavailable — Replace Disk was not started.",
                rawDetails: ""))
            return
        }
        let outcome = replaceDiskCoordinator.start(
            vm: current, typedName: typedName, path: path,
            using: client, jobManager: jobManager)
        if case .refused(let reason) = outcome {
            let line = "replace disk refused for \(current.name): \(String(describing: reason))"
            Logger.replaceDisk.info("\(line, privacy: .public)")
            present(TartOperationError(
                operation: "set",
                message: ReplaceDiskCopy.refusalMessage(for: reason, vmName: current.name),
                rawDetails: ""))
        }
    }

    // MARK: - Cache maintenance (prune)

    /// Prunes cache entries older than the retention age (caches only —
    /// VMs are never touched). The single-flight key is the namespaced
    /// `prune:caches` (never a VM name). tart prune prints nothing on
    /// success, so the completion summary is derived from the measured
    /// free-space delta on the storage volume.
    func startPrune(days: Int) {
        guard let client = makeTartClient() else { return }
        let home = client.environment["TART_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tart").path
        jobManager.start(kind: .prune) { context in
            let freeBefore = DiskSpace.freeBytes(atPath: home)
            context.report(PullProgress(fraction: nil, note: "pruning…"))
            let outcome = try client.prune(
                olderThanDays: days,
                onOutput: { _ in },
                registerCancel: { action in context.registerCancel(action) })
            if outcome == .cancelled || context.isCancelled { return }
            let freeAfter = DiskSpace.freeBytes(atPath: home)
            context.reportSummary(
                PruneSummary.compose(freeBefore: freeBefore, freeAfter: freeAfter))
        }
    }
}
