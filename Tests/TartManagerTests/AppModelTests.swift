import Testing
import Foundation
@testable import TartKit
@testable import TartManager

@Suite @MainActor struct AppModelTests {
    func makeIsolatedModel() -> AppModel {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(settings: AppSettings(defaults: defaults))
    }

    func makeTempDirectory() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func validChoicePersistsAndBecomesAvailable() {
        let dir = makeTempDirectory()
        let model = makeIsolatedModel()
        let result = model.attemptChooseStorage(path: dir)
        #expect(result == .valid(path: dir))
        #expect(model.settings.storagePath == dir)
        #expect(model.storageAvailability == .available(path: dir))
        #expect(model.requiresOnboarding == false)
    }

    @Test func appearanceLoadsSavedChoiceAndPersistsChanges() {
        let defaults = UserDefaults(suiteName: "AppearanceTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        let model = AppModel(settings: settings)
        #expect(model.appearance == .dark)
        model.appearance = .light
        #expect(settings.appearance == .light)
        model.appearance = .system
        #expect(settings.appearance == .system)
    }

    @Test func invalidChoiceIsRejectedAndNothingPersists() {
        let dir = makeTempDirectory()
        let model = makeIsolatedModel()
        let missing = dir + "/gone"
        let result = model.attemptChooseStorage(path: missing)
        #expect(result == .invalid(path: missing, reason: "Folder does not exist or is not a folder."))
        #expect(model.settings.storagePath == nil)
        #expect(model.requiresOnboarding)
    }

    @Test func invalidChoiceLeavesPreviousPathIntact() {
        let dir = makeTempDirectory()
        let model = makeIsolatedModel()
        _ = model.attemptChooseStorage(path: dir)
        let result = model.attemptChooseStorage(path: dir + "/gone")
        #expect(result.isValid == false)
        #expect(model.settings.storagePath == dir)
        #expect(model.storageAvailability == .available(path: dir))
    }

    @Test func readOnlyChoiceIsRejected() throws {
        let dir = makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir) }
        let model = makeIsolatedModel()
        let result = model.attemptChooseStorage(path: dir)
        #expect(result == .invalid(path: dir, reason: "Folder is not writable."))
        #expect(model.settings.storagePath == nil)
    }

    @Test func successfulResourceApplyPersistsDisplayRefitChoice() async throws {
        let dir = makeTempDirectory()
        let invocationFile = dir + "/invocation.txt"
        let binaryPath = dir + "/tart"
        let script = """
        #!/bin/sh
        if [ "$1" = "set" ]; then
          echo "$@" > "\(invocationFile)"
        fi
        exit 0
        """
        try script.write(toFile: binaryPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath)

        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(settings: AppSettings(defaults: defaults))
        model.settings.storagePath = dir
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: binaryPath)
        let vm = VMEntry(name: "vm-a", source: "local", running: false, state: "stopped",
                         diskSize: 40, diskUsage: 0, accessed: nil)
        model.inventoryService.updateFetch { [vm] }
        await model.inventoryService.refresh()

        await model.apply(fields: ResourceEditorFields(displayRefit: true), to: vm)

        #expect(model.settings.displayRefitPreference(for: vm.name) == true)
        #expect(try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "set vm-a --display-refit")
    }
}

// Appended by Issue 9 (findings 4, 15): the create gate and name-availability
// surface are tested, not just wired. Models use `makeIsolatedModel` (the
// file's existing convention) so no real UserDefaults state can leak in.
extension AppModelTests {
    @Test func isNameAvailableReflectsInventoryAndInFlightJobs() async {
        let model = makeIsolatedModel()
        model.inventoryService.updateFetch {
            [VMEntry(name: "vm-a", source: "local", running: false, state: "stopped",
                     diskSize: 0, diskUsage: 0, accessed: nil)]
        }
        await model.inventoryService.refresh()
        #expect(model.isNameAvailable("vm-a") == false)   // in inventory
        #expect(model.isNameAvailable("vm-b") == true)

        let gate = AppModelTestGate()
        model.jobManager.start(kind: .clone(name: "vm-b", source: "x:y")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        #expect(model.isNameAvailable("vm-b") == false)   // in-flight target (finding 4)
        #expect(model.isNameAvailable("-vm") == false)    // syntax (finding 11)
        gate.open()
        await model.jobManager.awaitIdle(timeout: 2)
        #expect(model.isNameAvailable("vm-b") == true)
    }

    @Test func startCreateRefusesDuplicateInFlightTarget() async {
        let model = makeIsolatedModel()
        let gate = AppModelTestGate()
        model.jobManager.start(kind: .clone(name: "vm-c", source: "x:y")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        // No tart client needed: the refusal is decided before any launch.
        let reason = model.startCreate(name: "vm-c", reference: "x:y")
        #expect(reason == "Another operation for “vm-c” is already running.")
        gate.open()
        await model.jobManager.awaitIdle(timeout: 2)
    }

    @Test func createBlockReasonGatesOnTartStorageAndSyntax() {
        // Fresh model: no storage configured and no tart → blocked.
        let fresh = makeIsolatedModel()
        #expect(fresh.createBlockReason(
            name: "vm-d",
            reference: "ghcr.io/cirruslabs/macos-tahoe-base:latest") != nil)
        // Leading-dash name rejected up front (finding 11).
        #expect(fresh.createBlockReason(
            name: "--help",
            reference: "ghcr.io/cirruslabs/macos-tahoe-base:latest")?
            .contains("must not start") == true)
        // Leading-dash reference rejected up front (finding 11).
        #expect(fresh.createBlockReason(
            name: "vm-d", reference: "--help")?
            .contains("reference") == true)
    }
}

/// Minimal latch for the appended AppModel tests.
final class AppModelTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _isOpen = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOpen
    }

    func open() {
        lock.lock()
        _isOpen = true
        lock.unlock()
    }
}

// IPSW creation: the first-run reminder routing, the completion flagging,
// and the disk-size start gate.
extension AppModelTests {
    func makeReminderModel() -> (model: AppModel, defaults: UserDefaults) {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(
            settings: AppSettings(defaults: defaults),
            firstRunReminder: FirstRunReminderStore(defaults: defaults))
        return (model, defaults)
    }

    /// A flagged IPSW-created VM routes through the reminder before running;
    /// the flag survives cancellation of the reminder and is only consumed by
    /// the first observed run.
    @Test func requestRunRoutesFlaggedIPSWVMThroughReminder() async {
        let (model, _) = makeReminderModel()
        let vm = VMEntry(name: "fresh-ipsw-vm", source: "local", running: false,
                         state: "stopped", diskSize: 64, diskUsage: 10, accessed: nil)

        model.firstRunReminder.flag(vm.name)
        await model.requestRun(vm: vm)
        #expect(model.firstRunVM?.name == "fresh-ipsw-vm")

        // Cancelling the reminder (firstRunVM = nil) does not consume the flag.
        model.firstRunVM = nil
        #expect(model.firstRunReminder.contains(vm.name))

        model.firstRunReminder.flag(vm.name)
        await model.requestRun(vm: vm)
        model.confirmFirstRun()
        #expect(model.firstRunVM == nil)
        // The flag is still pending until the inventory observes the VM
        // running — a failed run would remind again.
        #expect(model.firstRunReminder.contains(vm.name))

        // An unflagged VM runs immediately — no reminder presented.
        model.firstRunReminder.unflag(vm.name)
        await model.requestRun(vm: vm)
        #expect(model.firstRunVM == nil)
    }

    /// The flag is set when the create-from-IPSW job completes (the
    /// `onStateChange` wiring).
    @Test func completedCreateFromIPSWJobFlagsFirstRunReminder() async {
        let (model, _) = makeReminderModel()

        model.jobManager.start(kind: .createFromIPSW(name: "fresh-ipsw-vm")) { _ in }
        await model.jobManager.awaitIdle(timeout: 2)
        #expect(model.firstRunReminder.contains("fresh-ipsw-vm"))
    }

    /// The start gate refuses invalid disk sizes with a reason, instead of
    /// starting with a fallback value.
    @Test func createFromIPSWBlockReasonRejectsInvalidDiskSize() {
        let (model, _) = makeReminderModel()
        #expect(model.createFromIPSWBlockReason(name: "vm", diskSizeGB: 0) != nil)
        #expect(model.createFromIPSWBlockReason(name: "vm", diskSizeGB: -5) != nil)
        #expect(model.createFromIPSWBlockReason(name: "vm", diskSizeGB: 4097) != nil)
    }

    /// A darwin run triggers the clipboard-watchdog flow end to end: the
    /// recording stub sees the readiness probes, the agent kickstart, and the
    /// guest watchdog install — with zero user-facing surface.
    @Test func runOfADarwinVMKicksAndInstallsTheGuestClipboardWatchdog() async throws {
        let suite = "AppModelTests-clipboard-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let dir = makeTempDirectory()
        let model = AppModel(settings: AppSettings(defaults: defaults))
        _ = model.attemptChooseStorage(path: dir)

        let invocationFile = dir + "/invocation.txt"
        let configJSON =
            #"{"OS":"darwin","CPU":4,"Memory":8192,"Disk":40,"DiskFormat":"raw","Size":"27.123","Display":"1024x768"}"#
        let stubScript = """
        #!/bin/sh
        case "$1" in
          list) echo '[]' ;;
          get) printf '%s\\n' '\(configJSON)' ;;
          run) sleep 8; exit 0 ;;
          exec) echo "$@" >> "\(invocationFile)"; printf 'ready\\n' ;;
          *) exit 0 ;;
        esac
        """
        let stubPath = dir + "/tart"
        try stubScript.write(toFile: stubPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubPath)
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: stubPath)

        let vm = VMEntry(name: "vm-clip", source: "local", running: false, state: "stopped",
                         diskSize: 50, diskUsage: 10, accessed: nil)
        await model.requestRun(vm: vm)

        // The watchdog follow-up is fire-and-forget on a production deadline;
        // poll the stub's recording for both the kick and the install.
        let deadline = Date().addingTimeInterval(10)
        var text = ""
        while Date() < deadline {
            text = (try? String(contentsOfFile: invocationFile, encoding: .utf8)) ?? ""
            if text.contains("launchctl kickstart") && text.contains("launchctl bootstrap") { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(text.contains("launchctl kickstart -k gui/$(id -u)/org.cirruslabs.tart-guest-agent"))
        #expect(text.contains("launchctl bootstrap gui/$(id -u)"))
    }
}

// Registry operations: the "app stores nothing" guarantee, the in-flight
// guard, and the tart-unavailable refusal.
extension AppModelTests {
    /// Minimal stub fixture for the app-target tests: a `tart` that records
    /// its argv, captures stdin, and optionally blocks on a gate file (the
    /// in-flight test). One definition in this target — not a copy of
    /// TartKitTests' StubBinary, which SPM does not expose across targets.
    enum RegistryLoginStub {
        static func recording(captureStdinTo stdinFile: String,
                              waitForGate gateFile: String? = nil,
                              announceStart startedFile: String? = nil) -> (stub: String, invocationFile: String) {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
            let invocationFile = dir.appendingPathComponent("invocation.txt").path
            let stub = dir.appendingPathComponent("tart").path
            let announce = startedFile.map { "touch \"\($0)\"\n" } ?? ""
            let gate = gateFile.map { "while [ ! -f \"\($0)\" ]; do sleep 0.01; done\n" } ?? ""
            let script = """
            #!/bin/sh
            # Only login invocations are recorded/announced: the AppModel's
            # inventory poller invokes this stub for `list` too, and those
            # runs must be inert so they cannot corrupt the handshake files.
            if [ "$1" = "login" ]; then
              \(announce)  \(gate)  echo "$@" > "\(invocationFile)"
              cat > "\(stdinFile)"
            fi
            exit 0
            """
            try! script.write(toFile: stub, atomically: true, encoding: .utf8)
            try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
            return (stub, invocationFile)
        }
    }

    /// Sweeps the persistence sinks the app itself owns — the UserDefaults
    /// domains it uses plus non-directory files directly under Application
    /// Support — for a credential-shaped value. tart's Keychain is
    /// deliberately outside the sweep: that storage belongs to tart.
    func appOwnedStorageContains(_ token: String, defaults: UserDefaults) -> Bool {
        for domain in [defaults, UserDefaults.standard] {
            for value in domain.dictionaryRepresentation().values {
                if String(describing: value).contains(token) { return true }
            }
        }
        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first,
           let entries = try? fileManager.contentsOfDirectory(atPath: support.path) {
            for entry in entries {
                let path = support.appendingPathComponent(entry).path
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }
                guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                      let size = attributes[.size] as? Int, size < 2 * 1_048_576 else { continue }
                if let text = try? String(contentsOfFile: path, encoding: .utf8),
                   text.contains(token) { return true }
            }
        }
        return false
    }

    /// The "app stores nothing" guarantee, asserted automatically. The full
    /// AppModel login path runs against a recording stub; the unique token
    /// reaches tart via stdin, never argv, and is absent from every
    /// app-owned persistence sink afterwards.
    @Test func registryLoginDeliversSecretAndAppStoresNothing() async throws {
        let suite = "AppModelTests-registry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(settings: AppSettings(defaults: defaults))
        let dir = makeTempDirectory()
        _ = model.attemptChooseStorage(path: dir)

        let token = "tok-\(UUID().uuidString)"
        let stdinFile = dir + "/stdin.txt"
        let (stub, invocationFile) = RegistryLoginStub.recording(captureStdinTo: stdinFile)
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: stub)

        let result = await model.registryLogin(host: "ghcr.io", username: "ci-bot", password: token)

        #expect(result)
        #expect(model.activeError == nil)
        #expect(model.registryOperationInFlight == false)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "login ghcr.io --username ci-bot --password-stdin")
        #expect(!invocation.contains(token))
        let captured = try String(contentsOfFile: stdinFile, encoding: .utf8)
        #expect(captured.trimmingCharacters(in: .whitespacesAndNewlines) == token)
        #expect(!appOwnedStorageContains(token, defaults: defaults))
    }

    /// A second Sign In while one is in flight is refused — the guard is at
    /// the model, so even a UI that forgot to disable buttons cannot spawn
    /// concurrent `tart login` subprocesses.
    ///
    /// The handshake is filesystem-based, not a flag poll: the stub
    /// announces itself (marker file) before waiting on the gate. The model
    /// sets its in-flight flag before the subprocess launches and holds it
    /// until the stub exits, so once the marker exists the login is
    /// provably in flight — the assertion cannot miss a briefly-set flag.
    @Test func secondRegistryLoginWhileInFlightIsRefused() async throws {
        let model = makeIsolatedModel()
        let dir = makeTempDirectory()
        _ = model.attemptChooseStorage(path: dir)
        let gate = dir + "/gate"
        let started = dir + "/started"
        let (stub, invocationFile) = RegistryLoginStub.recording(
            captureStdinTo: dir + "/stdin.txt", waitForGate: gate, announceStart: started)
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: stub)

        let first = Task(priority: .high) { await model.registryLogin(host: "ghcr.io", username: "u", password: "p") }
        var startedObserved = false
        let deadline = Date().addingTimeInterval(60)
        while !startedObserved && Date() < deadline {
            if FileManager.default.fileExists(atPath: started) { startedObserved = true }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(startedObserved, Comment(rawValue: "stub never started — subprocess launch unavailable"))
        guard startedObserved else {
            try Data().write(to: URL(fileURLWithPath: gate))
            _ = await first.value
            return
        }
        // The marker exists, so the login is blocked on the gate with its
        // in-flight flag held true.
        #expect(model.registryOperationInFlight)

        let second = await model.registryLogin(host: "ghcr.io", username: "u", password: "p")
        #expect(second == false)                      // refused, not queued

        try Data().write(to: URL(fileURLWithPath: gate))  // release the first
        let firstResult = await first.value
        #expect(firstResult)
        #expect(model.registryOperationInFlight == false)
        let invocations = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocations == "login ghcr.io --username u --password-stdin")  // exactly one
    }

    /// Without tart (or storage), the operation refuses cleanly — logged at
    /// the model (verified manually in Task 6 Step 5) and never a
    /// half-presented state. The UI disables the buttons in this state.
    @Test func registryOperationsRefuseWhenTartIsUnavailable() async {
        let model = makeIsolatedModel()   // no storage, no prerequisite
        let result = await model.registryLogin(host: "ghcr.io", username: "u", password: "p")
        #expect(result == false)
        #expect(model.activeError == nil)             // gated in the UI; refusal is logged
        #expect(model.registryOperationInFlight == false)
    }
}
