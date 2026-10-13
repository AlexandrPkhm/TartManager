import Foundation
import os

/// Failures from tart invocations (raw capture; Issue 6 normalizes presentation).
/// One error surface for every way `list()` can fail — non-zero exit, launch
/// failure, timeout, undecodable output — so callers never have to handle
/// `ProcessRunnerError` or `DecodingError` directly.
public enum TartClientError: Error, Equatable, Sendable {
    case commandFailed(command: String, exitCode: Int32, stdout: String, stderr: String)
    case launchFailed(command: String, executable: String)
    case timedOut(command: String, timeout: TimeInterval)
    case decodingFailed(command: String, output: String)
    /// The child exited 0 without reading the input the app sent (the stdin
    /// write failed) — the credential never reached tart. Honest payload, no
    /// fabricated exit code.
    case stdinDeliveryFailed(command: String)
}

/// Executes tart CLI operations. Grows through the slices (`list` first).
public struct TartClient: Sendable {
    public let binaryPath: String
    public let runner: ProcessRunner
    public let environment: [String: String]
    /// Per-run deadline; defaults to the runner's. `list` is sub-second in
    /// practice, so the default 10 s deadline bounds even a wedged binary.
    public let timeout: TimeInterval
    /// Per-run deadline for registry authentication. Login round-trips to a
    /// registry's auth endpoint, so it gets a longer deadline than the
    /// `timeout` used for local quick commands — still bounded, so an
    /// unreachable registry degrades to `.timedOut`.
    public let authTimeout: TimeInterval
    private let suspendableSessionReader: @Sendable (String) -> Bool?

    /// The optional session reader accepts a VM directory and returns its
    /// current run flag, or nil when unknown. Defaults to native process inspection.
    public init(binaryPath: String,
                runner: ProcessRunner = ProcessRunner(),
                environment: [String: String] = [:],
                timeout: TimeInterval = ProcessRunner.defaultTimeout,
                authTimeout: TimeInterval = 30,
                suspendableSessionReader: (@Sendable (String) -> Bool?)? = nil) {
        self.binaryPath = binaryPath
        self.runner = runner
        self.environment = environment
        self.timeout = timeout
        self.authTimeout = authTimeout
        self.suspendableSessionReader = suspendableSessionReader ?? { VMRunSession.read(atVMDirectory: $0) }
    }

    /// Subprocess deadline for stop: generous enough that tart's own 30 s
    /// graceful period — plus its automatic force termination when the grace
    /// elapses — always completes. `ProcessRunner.defaultTimeout` (10 s) is
    /// too short for a command that legitimately blocks that long. Still
    /// finite, so a wedged binary degrades to `.timedOut`, never a hang.
    public static let stopCommandTimeout: TimeInterval = 90

    /// Lists local VMs and OCI images in the configured storage.
    /// Every failure mode surfaces as a `TartClientError`. Local entries are
    /// enriched with the guest OS from their on-disk `config.json` (which
    /// `tart list` omits), so UI gates and run decisions key on one value.
    public func list() throws -> [VMEntry] {
        let result: ProcessResult
        do {
            result = try runner.run(
                binaryPath, ["list", "--format", "json"],
                environment: environment, timeout: timeout)
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "list")
        } catch {
            throw TartClientError.launchFailed(command: "list", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(
                command: "list", exitCode: result.exitCode,
                stdout: result.stdout, stderr: result.stderr)
        }
        let entries: [VMEntry]
        do {
            entries = try Self.decodeEntries(Data(result.stdout.utf8))
        } catch {
            throw TartClientError.decodingFailed(command: "list", output: result.stdout)
        }
        return entries.map { entry in
            guard entry.isLocal,
                  let directory = Self.vmStoragePath(environment: environment, name: entry.name)
            else { return entry }
            let vm = entry.withGuestOS(VMGuestOS.read(atVMDirectory: directory))
            guard vm.running, vm.supportsSuspend else { return vm }
            let session = suspendableSessionReader(directory)
            if session == nil {
                Logger.suspend.debug("Suspend hidden for '\(vm.name, privacy: .public)': run flag unknown")
            }
            return vm.withSuspendableSession(session)
        }
    }

    /// Rechecks the live process before suspend rather than trusting a stale row.
    func canSuspend(name: String) -> Bool {
        guard let directory = Self.vmStoragePath(environment: environment, name: name),
              VMGuestOS.supportsSuspend(VMGuestOS.read(atVMDirectory: directory)) else { return false }
        return suspendableSessionReader(directory) == true
    }

    private static func mapping(_ error: ProcessRunnerError, command: String) -> TartClientError {
        switch error {
        case .failedToLaunch(let executable):
            return .launchFailed(command: command, executable: executable)
        case .timedOut(let command, let timeout):
            return .timedOut(command: command, timeout: timeout)
        case .inputWriteFailed(let command):
            return .stdinDeliveryFailed(command: command)
        }
    }

    public static func decodeEntries(_ data: Data) throws -> [VMEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VMEntry].self, from: data)
    }
}

extension TartClient {
    /// tart's per-VM control socket filename, bound relative to the run
    /// process's working directory by tart 2.32.1.
    public static let controlSocketFilename = "control.sock"

    /// Raw `$TART_HOME/vms/<name>` path, or nil when `TART_HOME` is absent
    /// from the injected environment or the directory does not exist (a
    /// run tart itself will refuse). Built by pure string concatenation:
    /// `URL`'s path accessors percent-encode (a space becomes `%20`),
    /// which is precisely the tart bug the working-directory contract
    /// works around, so the path never round-trips through `URL` before
    /// it reaches `Process.currentDirectoryURL`.
    public static func vmStoragePath(environment: [String: String], name: String) -> String? {
        guard let tartHome = environment["TART_HOME"] else { return nil }
        let path = tartHome + "/vms/" + name
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return path
    }
}

extension TartClient {
    /// Runs a VM as a detached windowed process, sharing the given host
    /// folders. macOS guests launch in the suspend-capable configuration
    /// (`--suspendable`, enabling the Suspend feature); Linux guests omit the
    /// flag because tart 2.32 refuses it for non-macOS guests ("You can only
    /// suspend macOS VMs", exit 64) — the refusal that made every Linux VM
    /// launch fail. `shares` defaults to empty, so callers that do not pass it
    /// reproduce the pre-feature argv `run --suspendable <name>` byte-for-byte
    /// for macOS guests; the window and log defaults stay the shared constants
    /// from Issue 4.
    ///
    /// Working-directory contract: the child launches from
    /// `$TART_HOME/vms/<name>` whenever that directory exists. tart 2.32.1
    /// chdirs there itself before binding its control socket, but the
    /// chdir target is percent-encoded and fails on storage paths with
    /// spaces — the socket then silently lands in the child's cwd, where
    /// only an exec started from that same directory can find it. Pinning
    /// the cwd to the VM directory restores the intended per-VM socket
    /// location without depending on tart's broken chdir.
    public func runVM(
        name: String,
        shares: [VMFolderShare] = [],
        earlyFailureWindow: TimeInterval = DetachedLaunchConfiguration.defaultEarlyFailureWindow,
        logDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> DetachedProcessHandle {
        let workingDirectory = Self.vmStoragePath(environment: environment, name: name)
        // The guest OS is a property of the VM, not the caller: reading it
        // here keeps every run path (first run, resume, future callers) on
        // the same argv rule with no way to reintroduce the Linux refusal.
        let guestOS = workingDirectory.flatMap { VMGuestOS.read(atVMDirectory: $0) }
        let suspendable = VMGuestOS.supportsSuspend(guestOS)
        var arguments = ["run"]
        if suspendable {
            arguments.append("--suspendable")
        }
        for share in shares {
            arguments += ["--dir", share.dirArgument]
        }
        arguments.append(name)
        // Assembled in parts: one long interpolated logger call exceeds the
        // Swift 5 mode type checker's budget.
        let summary = shares.map { "\($0.name)\($0.customTag.map { "@\($0)" } ?? "")" }
            .joined(separator: ", ")
        let argvLine = "run argv for \(name): \(shares.count) --dir share(s) (\(summary))"
        Logger.sharedFolders.info("\(argvLine, privacy: .public)")
        let configLine = "run configuration for \(name): guestOS=\(guestOS ?? "unknown"), "
            + "suspendable=\(suspendable)"
        Logger.client.info("\(configLine, privacy: .public)")

        // Stale-socket hygiene: `RunCoordinator` single-flights launches, so
        // any leftover `control.sock` in the VM directory belongs to a dead
        // run; leaving it would make this run's bind fail with EADDRINUSE
        // — silently, inside tart's fire-and-forget control-socket task.
        if let workingDirectory {
            let staleSocket = workingDirectory + "/" + Self.controlSocketFilename
            if FileManager.default.fileExists(atPath: staleSocket) {
                try? FileManager.default.removeItem(atPath: staleSocket)
                let line = "removed stale \(Self.controlSocketFilename) for \(name)"
                Logger.client.info("\(line, privacy: .public)")
            }
        }

        let launcher = DetachedProcessLauncher()
        do {
            return try launcher.launch(DetachedLaunchConfiguration(
                binaryPath: binaryPath,
                arguments: arguments,
                environment: environment,
                earlyFailureWindow: earlyFailureWindow,
                logDirectory: logDirectory,
                workingDirectory: workingDirectory))
        } catch DetachedLauncherError.exitedQuickly(let exitCode, let output) {
            let failureLine = "run failed within the early-failure window for \(name) "
                + "(\(shares.count) share(s)); exit \(exitCode): \(output)"
            Logger.sharedFolders.error("\(failureLine, privacy: .public)")
            throw TartClientError.commandFailed(command: "run", exitCode: exitCode,
                                                 stdout: "", stderr: output)
        } catch DetachedLauncherError.failedToLaunch(let path) {
            throw TartClientError.commandFailed(command: "run", exitCode: -1,
                                                 stdout: "", stderr: "Failed to launch \(path)")
        }
    }
}

extension TartClient {
    /// Stops a VM. `timeout == nil` passes **no flag** — tart's own 30 s
    /// graceful default applies (force-fallback included); `timeout == 0`
    /// terminates immediately (Force Stop); any other value sets an
    /// explicit grace period in seconds.
    ///
    /// `async` because the command blocks for up to the grace period: the
    /// blocking `ProcessRunner` call executes on a detached task so the
    /// cooperative executor is never pinned (high-level operations are
    /// asynchronous).
    public func stop(name: String, timeout: Int? = nil) async throws {
        let binaryPath = binaryPath
        let runner = runner
        let environment = environment
        var arguments = ["stop", name]
        if let timeout {
            arguments += ["--timeout", String(timeout)]
        }
        let result: ProcessResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try runner.run(binaryPath, arguments, environment: environment,
                               timeout: Self.stopCommandTimeout)
            }.value
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "stop")
        } catch {
            throw TartClientError.launchFailed(command: "stop", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(command: "stop", exitCode: result.exitCode,
                                                 stdout: result.stdout, stderr: result.stderr)
        }
    }
}

extension TartClient {
    /// Suspends a running VM started with the suspendable configuration.
    /// `async` because the command blocks until tart parks the session: the
    /// blocking `ProcessRunner` call executes on a detached task so the
    /// cooperative executor is never pinned. Runs under the client's
    /// subprocess deadline (`timeout`, the app-wide default).
    public func suspend(name: String) async throws {
        let binaryPath = binaryPath
        let runner = runner
        let environment = environment
        let timeout = timeout
        let result: ProcessResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try runner.run(binaryPath, ["suspend", name], environment: environment,
                               timeout: timeout)
            }.value
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "suspend")
        } catch {
            throw TartClientError.launchFailed(command: "suspend", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(command: "suspend", exitCode: result.exitCode,
                                                 stdout: result.stdout, stderr: result.stderr)
        }
    }
}

extension TartClient {
    /// Reads a VM's configuration (`tart get --format json`). Failures are
    /// logged and thrown as the standard client error.
    public func get(name: String) throws -> VMConfigInfo {
        let result: ProcessResult
        do {
            result = try runner.run(binaryPath, ["get", name, "--format", "json"],
                                    environment: environment, timeout: timeout)
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "get")
        } catch {
            throw TartClientError.launchFailed(command: "get", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            Logger.client.error(
                "tart get \(name) failed (exit \(result.exitCode)): \(result.stderr, privacy: .public)")
            throw TartClientError.commandFailed(command: "get", exitCode: result.exitCode,
                                                stdout: result.stdout, stderr: result.stderr)
        }
        do {
            return try JSONDecoder().decode(VMConfigInfo.self, from: Data(result.stdout.utf8))
        } catch {
            Logger.client.error(
                "tart get \(name) output undecodable: \(result.stdout, privacy: .public)")
            throw TartClientError.decodingFailed(command: "get", output: result.stdout)
        }
    }

    /// Resolves the guest IP, or nil when unavailable (stopped/booting/no lease).
    /// Absence is a state, not a failure — nil is returned, never thrown —
    /// while launch/timeout failures throw the standard client error.
    public func ip(name: String) throws -> String? {
        let result: ProcessResult
        do {
            result = try runner.run(binaryPath, ["ip", name],
                                    environment: environment, timeout: timeout)
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "ip")
        } catch {
            throw TartClientError.launchFailed(command: "ip", executable: binaryPath)
        }
        guard result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TartClient {
    /// Runs a shell command inside a running VM through `tart exec` and
    /// returns its trimmed stdout on success. Throws the standard
    /// `TartClientError.commandFailed` when the guest agent is unreachable
    /// or the command exits non-zero — callers polling for guest readiness
    /// treat thrown errors as "not ready yet", never surface them raw.
    /// The command string runs under the guest's `sh -lc`, so constructs
    /// like `$(id -u)` expand against the guest, not the host.
    /// Runs with `$TART_HOME/vms/<name>` as its working directory — the
    /// same per-VM cwd `runVM` pins its runs to, because tart 2.32.1's
    /// control socket lands in (and is only reachable from) that
    /// directory on space-containing storage paths.
    public func exec(name: String, command: String) throws -> String {
        try Self.rejectLeadingDash(command: "exec", values: [name])
        let result: ProcessResult
        do {
            result = try runner.run(binaryPath,
                                    ["exec", name, "sh", "-lc", command],
                                    environment: environment,
                                    timeout: timeout,
                                    workingDirectory: Self.vmStoragePath(environment: environment, name: name))
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "exec")
        } catch {
            throw TartClientError.launchFailed(command: "exec", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(command: "exec", exitCode: result.exitCode,
                                                 stdout: result.stdout, stderr: result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TartClient {
    /// Applies a resource update. Callers (AppModel) validate first; this
    /// method is a pure CLI boundary. Runs under the client's per-run
    /// deadline so a wedged tart surfaces as `.timedOut`, never a hang.
    public func set(name: String, update: VMResourceUpdate) throws {
        try runSet(name: name, extraArguments: update.arguments, commandLabel: "set")
    }

    /// Regenerates the VM's MAC address (tart acts regardless of guest OS).
    public func regenerateMAC(name: String) throws {
        try runSet(name: name, extraArguments: ["--random-mac"], commandLabel: "set")
    }

    /// Regenerates the VM's serial number. tart only randomizes serials on
    /// Darwin guests (tart 2.32 `Set.swift`); the UI disables/annotates this
    /// for known non-Darwin guests.
    public func regenerateSerial(name: String) throws {
        try runSet(name: name, extraArguments: ["--random-serial"], commandLabel: "set")
    }

    private func runSet(name: String, extraArguments: [String], commandLabel: String) throws {
        try runTart(["set", name] + extraArguments, commandLabel: commandLabel)
    }
}

extension TartClient {
    /// The single run + exit-code check + typed-throw boilerplate for quick
    /// tart commands: `runSet` and `login`/`logout` all route through here
    /// instead of re-implementing it. `input` is delivered via stdin
    /// (`--password-stdin`); a nil `deadline` falls back to the client's
    /// quick-command `timeout`.
    private func runTart(_ arguments: [String],
                         commandLabel: String,
                         input: String? = nil,
                         timeout deadline: TimeInterval? = nil) throws {
        let result: ProcessResult
        do {
            result = try runner.run(binaryPath, arguments,
                                    environment: environment,
                                    timeout: deadline ?? timeout,
                                    input: input)
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: commandLabel)
        } catch {
            throw TartClientError.launchFailed(command: commandLabel, executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(command: commandLabel,
                                                exitCode: result.exitCode,
                                                stdout: result.stdout,
                                                stderr: result.stderr)
        }
    }

    /// Signs in to a registry. The secret is delivered via stdin
    /// (`--password-stdin`); the app never stores credentials — tart keeps
    /// them in the user's Keychain. Empty fields and hostile hosts throw
    /// `RegistryArgumentError` before any subprocess runs.
    public func login(host: String, username: String, password: String) throws {
        try RegistryCredentialRules.validate(host: host, username: username,
                                             password: password, command: "login")
        try runTart(["login", host, "--username", username, "--password-stdin"],
                    commandLabel: "login", input: password, timeout: authTimeout)
    }

    /// Removes tart's stored credentials for a host.
    public func logout(host: String) throws {
        try RegistryCredentialRules.validate(host: host, command: "logout")
        try runTart(["logout", host], commandLabel: "logout", timeout: authTimeout)
    }
}

extension TartClient {
    /// Outcome of a streamed, cancellable `tart import`.
    public enum ImportOutcome: Equatable, Sendable {
        case completed
        case cancelled
    }

    /// Runs `tart import <path> <name>` to completion. The client owns the
    /// whole run (PRD Tart CLI Client contract): streaming accumulation,
    /// cancellation wiring, and failure normalization into
    /// `TartClientError.launchFailed`/`.commandFailed` with command "import".
    /// Indeterminate by design — tart import prints no parseable percentages —
    /// so `onOutput` receives raw chunks for error capture/logging only.
    public func importArchive(
        at path: String,
        to name: String,
        onOutput: @escaping @Sendable (String) -> Void,
        registerCancel: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) throws -> ImportOutcome {
        try Self.rejectLeadingDash(command: "import", values: [path, name])
        let accumulator = TextAccumulator()
        let process: StreamingProcess
        do {
            process = try StreamingProcess.launch(
                binaryPath: binaryPath,
                arguments: ["import", path, name],
                environment: environment,
                onOutput: { chunk in
                    accumulator.append(chunk)
                    onOutput(chunk)
                })
        } catch {
            throw TartClientError.launchFailed(command: "import", executable: binaryPath)
        }
        registerCancel { process.cancel() }
        let exitCode = process.waitForExit()
        if process.wasCancelled { return .cancelled }
        guard exitCode == 0 else {
            throw TartClientError.commandFailed(command: "import", exitCode: exitCode,
                                                stdout: "", stderr: accumulator.value)
        }
        return .completed
    }

    /// Deletes a (stopped) VM. Destructive — callers gate it behind typed
    /// confirmations (PRD SC-006); used for partial-import cleanup here and by
    /// the Issue 17 async delete job. Bounded by `timeout` so a wedged tart
    /// cannot block cleanup forever; nil uses the client's stored deadline
    /// (same convention as list/get/ip/set).
    public func delete(name: String,
                       timeout: TimeInterval? = nil) throws {
        try Self.rejectLeadingDash(command: "delete", values: [name])
        let result: ProcessResult
        do {
            result = try runner.run(binaryPath, ["delete", name],
                                    environment: environment,
                                    timeout: timeout ?? self.timeout)
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "delete")
        } catch {
            throw TartClientError.launchFailed(command: "delete", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(command: "delete", exitCode: result.exitCode,
                                                stdout: result.stdout, stderr: result.stderr)
        }
    }

    /// User-controlled path/name values must never be parsed as tart flags.
    /// Rejection is chosen over inserting `--` because it is correct on every
    /// tart version (see Research).
    static func rejectLeadingDash(command: String, values: [String]) throws {
        if let bad = values.first(where: { $0.hasPrefix("-") }) {
            throw TartClientError.commandFailed(
                command: command, exitCode: -1, stdout: "",
                stderr: "refusing argument '\(bad)' beginning with '-' (flag injection guard)")
        }
    }
}

extension TartClient {
    /// Renames a stopped local VM (`tart rename <old> <new>`). Mirrors
    /// `delete` (Issue 11): leading-dash values are refused before any
    /// subprocess and failures map through the shared normalization.
    public func rename(from: String, to: String) throws {
        try Self.rejectLeadingDash(command: "rename", values: [from, to])
        let result: ProcessResult
        do {
            result = try runner.run(binaryPath, ["rename", from, to],
                                    environment: environment, timeout: timeout)
        } catch let error as ProcessRunnerError {
            throw Self.mapping(error, command: "rename")
        } catch {
            throw TartClientError.launchFailed(command: "rename", executable: binaryPath)
        }
        guard result.exitCode == 0 else {
            throw TartClientError.commandFailed(command: "rename", exitCode: result.exitCode,
                                                stdout: result.stdout, stderr: result.stderr)
        }
    }
}

extension TartClient {
    /// Replaces a stopped VM's disk contents from a source disk image.
    /// Destructive and long-running: the full copy can take minutes on
    /// non-APFS volumes, so this streams through `StreamingProcess` — which
    /// carries no `ProcessRunner` deadline — instead of the quick `runSet`
    /// wrapper, and accumulates output only for error capture. The app gates
    /// it behind the typed-name confirmation and `ReplaceDiskGuard` before
    /// ever calling it and runs it as a non-cancellable job.
    public func replaceDisk(name: String, withPath path: String,
                            onOutput: @escaping @Sendable (String) -> Void = { _ in }) throws {
        try Self.rejectLeadingDash(command: "set", values: [path])
        let accumulator = TextAccumulator()
        let process: StreamingProcess
        do {
            process = try StreamingProcess.launch(
                binaryPath: binaryPath,
                arguments: ["set", name, "--disk", path],
                environment: environment,
                onOutput: { chunk in
                    accumulator.append(chunk)
                    onOutput(chunk)
                })
        } catch {
            throw TartClientError.launchFailed(command: "set", executable: binaryPath)
        }
        let exitCode = process.waitForExit()
        guard exitCode == 0 else {
            throw TartClientError.commandFailed(command: "set", exitCode: exitCode,
                                                stdout: "", stderr: accumulator.value)
        }
    }
}

extension TartClient {
    /// How a clone run ended.
    public enum CloneExit: Equatable, Sendable {
        case completed
        case cancelled
    }

    /// Runs `tart clone <source> <name>` to completion. The client owns
    /// progress parsing and deduplication and failure normalization
    /// (finding 8): the app layer only registers cancellation and consumes
    /// the outcome.
    ///
    /// - `onProgress` receives only actual progress changes (finding 12).
    /// - `registerCancel` receives a cancel action that SIGTERMs the
    ///   subprocess (escalating to SIGKILL when ignored — finding 9); call
    ///   it once, immediately, to wire the action into the caller's cancel
    ///   registry.
    /// - On a nonzero exit (not cancelled) throws
    ///   `TartClientError.commandFailed(command: "clone", …)` whose `stderr`
    ///   is the extracted failure line so the standard sheet shows tart's
    ///   message, not a progress banner (finding 2). A launch failure maps
    ///   to `.launchFailed(command: "clone", …)` — the operation label is
    ///   always "clone" (finding 16).
    public func clone(
        source: String,
        to name: String,
        onProgress: @escaping @Sendable (PullProgress) -> Void,
        registerCancel: (@escaping @Sendable () -> Void) -> Void = { _ in }
    ) throws -> CloneExit {
        let tracker = PullProgressTracker()
        let process: StreamingProcess
        do {
            process = try StreamingProcess.launch(
                binaryPath: binaryPath,
                arguments: ["clone", source, name],
                environment: environment,
                onOutput: { chunk in
                    if let progress = tracker.consume(chunk) {
                        onProgress(progress)
                    }
                })
        } catch let error as ProcessRunnerError {
            // Mirrors Issue 3's `mapping(_:command:)` — every launch failure
            // here reads "clone" (finding 16).
            switch error {
            case .failedToLaunch:
                throw TartClientError.launchFailed(command: "clone", executable: binaryPath)
            case .timedOut(let command, let timeout):
                throw TartClientError.timedOut(command: command, timeout: timeout)
            case .inputWriteFailed(let command):
                throw TartClientError.stdinDeliveryFailed(command: command)
            }
        }
        registerCancel { [process] in process.cancel() }
        let exitCode = process.waitForExit()
        if process.wasCancelled {
            return .cancelled
        }
        guard exitCode == 0 else {
            throw TartClientError.commandFailed(
                command: "clone", exitCode: exitCode,
                stdout: process.combinedOutput,
                stderr: tracker.failureLine ?? "")
        }
        return .completed
    }
}

extension TartClient {
    /// How an export run ended.
    public enum ExportOutcome: Equatable, Sendable {
        case completed
        case cancelled
    }

    /// Runs `tart export <name> <path>` to completion. Indeterminate by
    /// design — tart export prints no parseable percentages — so there is no
    /// progress callback: `onOutput` receives raw chunks for error capture
    /// and logging only. `PullProgressParser` is clone/pull-only and is never
    /// involved here (finding 10). The client owns accumulation, cancellation
    /// wiring, and failure normalization into `TartClientError` with command
    /// "export".
    public func export(
        name: String,
        to path: String,
        onOutput: @escaping @Sendable (String) -> Void,
        registerCancel: (@escaping @Sendable () -> Void) -> Void = { _ in }
    ) throws -> ExportOutcome {
        let accumulator = TextAccumulator()
        let process: StreamingProcess
        do {
            process = try StreamingProcess.launch(
                binaryPath: binaryPath,
                arguments: ["export", name, path],
                environment: environment,
                onOutput: { chunk in
                    accumulator.append(chunk)
                    onOutput(chunk)
                })
        } catch let error as ProcessRunnerError {
            switch error {
            case .failedToLaunch:
                throw TartClientError.launchFailed(command: "export", executable: binaryPath)
            case .timedOut(let command, let timeout):
                throw TartClientError.timedOut(command: command, timeout: timeout)
            case .inputWriteFailed(let command):
                throw TartClientError.stdinDeliveryFailed(command: command)
            }
        }
        registerCancel { [process] in process.cancel() }
        let exitCode = process.waitForExit()
        if process.wasCancelled {
            return .cancelled
        }
        guard exitCode == 0 else {
            throw TartClientError.commandFailed(command: "export", exitCode: exitCode,
                                                stdout: "", stderr: accumulator.value)
        }
        return .completed
    }
}

extension TartClient {
    /// Outcome of a streamed, cancellable `tart create --from-ipsw`.
    public enum CreateOutcome: Equatable, Sendable {
        case completed
        case cancelled
    }

    /// Runs `tart create <name> --from-ipsw <path-or-latest> --disk-size N` to
    /// completion. The client owns the whole run (PRD Tart CLI Client
    /// contract): the leading-dash guard, bounded output accumulation (no
    /// parsing — restore output is indeterminate), cancellation wiring, and
    /// failure normalization into `TartClientError.commandFailed(command:
    /// "create", …)`. The known cross-version refusal is detected downstream
    /// by `TartErrorAnalyzer` from the captured stderr.
    public func createFromIPSW(
        name: String,
        ipsw: String,
        diskSizeGB: Int,
        onOutput: @escaping @Sendable (String) -> Void,
        registerCancel: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) throws -> CreateOutcome {
        try Self.rejectLeadingDash(command: "create", values: [name, ipsw])
        let accumulator = TextAccumulator()
        let process: StreamingProcess
        do {
            process = try StreamingProcess.launch(
                binaryPath: binaryPath,
                arguments: ["create", name, "--from-ipsw", ipsw,
                            "--disk-size", String(diskSizeGB)],
                environment: environment,
                onOutput: { chunk in
                    accumulator.append(chunk)
                    onOutput(chunk)
                })
        } catch {
            throw TartClientError.launchFailed(command: "create", executable: binaryPath)
        }
        registerCancel { process.cancel() }
        let exitCode = process.waitForExit()
        if process.wasCancelled { return .cancelled }
        guard exitCode == 0 else {
            throw TartClientError.commandFailed(command: "create", exitCode: exitCode,
                                                stdout: "", stderr: accumulator.value)
        }
        return .completed
    }
}

extension TartClient {
    /// How a prune run ended.
    public enum PruneOutcome: Equatable, Sendable {
        case completed
        case cancelled
    }

    /// Runs `tart prune --entries caches --older-than N` to completion.
    ///
    /// Verified against the tart 2.32.0 sources: prune emits nothing on the
    /// success path (`Prune.swift`'s `delete()` prints no output), so
    /// `onOutput` receives raw chunks for error capture only — the
    /// completion summary is computed from measured disk state by the
    /// caller, never from captured output. The client owns accumulation,
    /// cancellation wiring, and failure normalization with command "prune",
    /// the same high-level streaming shape as import/export.
    public func prune(
        olderThanDays: Int,
        onOutput: @escaping @Sendable (String) -> Void,
        registerCancel: (@escaping @Sendable () -> Void) -> Void = { _ in }
    ) throws -> PruneOutcome {
        guard olderThanDays > 0 else {
            throw TartClientError.commandFailed(
                command: "prune", exitCode: -1, stdout: "",
                stderr: "Invalid retention age: \(olderThanDays) days (must be positive).")
        }
        let accumulator = TextAccumulator()
        let process: StreamingProcess
        do {
            process = try StreamingProcess.launch(
                binaryPath: binaryPath,
                arguments: ["prune", "--entries", "caches",
                            "--older-than", String(olderThanDays)],
                environment: environment,
                onOutput: { chunk in
                    accumulator.append(chunk)
                    onOutput(chunk)
                })
        } catch let error as ProcessRunnerError {
            switch error {
            case .failedToLaunch:
                throw TartClientError.launchFailed(command: "prune", executable: binaryPath)
            case .timedOut(let command, let timeout):
                throw TartClientError.timedOut(command: command, timeout: timeout)
            case .inputWriteFailed(let command):
                throw TartClientError.stdinDeliveryFailed(command: command)
            }
        }
        registerCancel { [process] in process.cancel() }
        let exitCode = process.waitForExit()
        if process.wasCancelled {
            return .cancelled
        }
        guard exitCode == 0 else {
            throw TartClientError.commandFailed(command: "prune", exitCode: exitCode,
                                                stdout: "", stderr: accumulator.value)
        }
        return .completed
    }
}
