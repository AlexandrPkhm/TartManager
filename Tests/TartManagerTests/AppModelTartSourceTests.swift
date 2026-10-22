import Testing
import Foundation
@testable import TartKit
@testable import TartManager

/// The tart source wiring in `AppModel`: the default-source decision, the
/// one-time prompt, gated switches, the custom path, and client rebuilds.
@Suite @MainActor struct AppModelTartSourceTests {
    /// A fake `tart` in its own folder: prints `version` for `--version`,
    /// answers `list` with `[]`, and appends every other invocation (with
    /// its `TART_HOME`) to `invocation.txt`. TartKitTests' `StubBinary` is
    /// not visible to this target.
    struct TartStub {
        let path: String
        let invocationFile: String

        init(version: String) {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
            try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            path = dir + "/tart"
            invocationFile = dir + "/invocation.txt"
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then printf '%s' "\(version)"; exit 0; fi
            if [ "$1" = "list" ]; then echo '[]'; exit 0; fi
            echo "$@ TART_HOME=$TART_HOME" >> "\(invocationFile)"
            exit 0
            """
            try! script.write(toFile: path, atomically: true, encoding: .utf8)
            try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }

        /// The complete lines recorded so far, waiting up to `timeout` for `count`.
        func lines(count: Int, timeout: TimeInterval = 5) async -> [String] {
            let deadline = Date().addingTimeInterval(timeout)
            var lines = Self.completeLines(invocationFile)
            while lines.count < count, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
                lines = Self.completeLines(invocationFile)
            }
            return lines
        }

        private static func completeLines(_ path: String) -> [String] {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
            var lines = content.components(separatedBy: "\n")
            lines.removeLast()
            return lines
        }
    }

    struct Fixture {
        let model: AppModel
        let storage: String
    }

    private func makeFixture(bundled: TartStub?, installed: TartStub?,
                             storedSource: TartSource? = nil) -> Fixture {
        let suite = "AppModelTartSourceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
        try! FileManager.default.createDirectory(atPath: storage, withIntermediateDirectories: true)
        settings.storagePath = storage
        settings.cachePrunePolicy = .manual
        settings.tartSource = storedSource
        let checker = PrerequisiteChecker(
            bundledExecutablePath: bundled?.path,
            locator: TartLocator(searchPath: "",
                                 wellKnownLocations: [installed?.path ?? "/nonexistent/tart"]),
            verify: { _ in .valid })
        let model = AppModel(settings: settings, updater: FakeUpdater(), prerequisiteChecker: checker)
        return Fixture(model: model, storage: storage)
    }

    /// Runs a check (or waits for the one in flight) to completion.
    private func check(_ model: AppModel) async {
        if !model.isCheckingPrerequisite { model.checkPrerequisite() }
        await waitForCheck(model)
    }

    private func waitForCheck(_ model: AppModel) async {
        let deadline = Date().addingTimeInterval(10)
        while model.isCheckingPrerequisite, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Default source

    @Test func firstCheckWithBothOkPromptsAndUsesInstalled() async {
        let fixture = makeFixture(bundled: TartStub(version: "2.41.1"),
                                  installed: TartStub(version: "2.32.1"))
        await check(fixture.model)
        #expect(fixture.model.pendingTartSourcePrompt != nil)
        #expect(fixture.model.prerequisite?.source == .installed)
        #expect(fixture.model.prerequisite?.isSatisfied == true)
        #expect(fixture.model.settings.tartSource == nil)
    }

    @Test func firstCheckWithoutBundledStoresInstalled() async {
        let fixture = makeFixture(bundled: nil, installed: TartStub(version: "2.32.1"))
        await check(fixture.model)
        #expect(fixture.model.settings.tartSource == .installed)
        #expect(fixture.model.pendingTartSourcePrompt == nil)
    }

    @Test func firstCheckWithOnlyBundledOkStoresBundled() async {
        let bundled = TartStub(version: "2.41.1")
        let fixture = makeFixture(bundled: bundled, installed: nil)
        await check(fixture.model)
        #expect(fixture.model.settings.tartSource == .bundled)
        #expect(fixture.model.prerequisite?.binaryPath == bundled.path)
        #expect(fixture.model.tartReport?.selected == .bundled)
    }

    @Test func promptAnswerStoresChoice() async {
        let bundled = TartStub(version: "2.41.1")
        let fixture = makeFixture(bundled: bundled, installed: TartStub(version: "2.32.1"))
        await check(fixture.model)
        fixture.model.answerTartSourcePrompt(.bundled)
        await waitForCheck(fixture.model)
        #expect(fixture.model.settings.tartSource == .bundled)
        #expect(fixture.model.pendingTartSourcePrompt == nil)
        #expect(fixture.model.prerequisite?.binaryPath == bundled.path)
    }

    @Test func storedPreferenceSkipsPrompt() async {
        let fixture = makeFixture(bundled: TartStub(version: "2.41.1"),
                                  installed: TartStub(version: "2.32.1"), storedSource: .installed)
        await check(fixture.model)
        #expect(fixture.model.pendingTartSourcePrompt == nil)
        #expect(fixture.model.prerequisite?.source == .installed)
    }

    @Test func promptStaysUntilAnswered() async {
        let fixture = makeFixture(bundled: TartStub(version: "2.41.1"),
                                  installed: TartStub(version: "2.32.1"))
        await check(fixture.model)
        await check(fixture.model)
        #expect(fixture.model.pendingTartSourcePrompt != nil)
        #expect(fixture.model.settings.tartSource == nil)
    }

    // MARK: Switching

    @Test func switchRebuildsClient() async {
        let bundled = TartStub(version: "2.41.1")
        let fixture = makeFixture(bundled: bundled, installed: TartStub(version: "2.32.1"),
                                  storedSource: .installed)
        await check(fixture.model)
        #expect(fixture.model.setTartSource(.bundled))
        await waitForCheck(fixture.model)
        #expect(fixture.model.makeTartClient()?.binaryPath == bundled.path)
    }

    @Test func switchRefusedWhileJobRuns() async throws {
        let fixture = makeFixture(bundled: TartStub(version: "2.41.1"),
                                  installed: TartStub(version: "2.32.1"), storedSource: .installed)
        await check(fixture.model)
        let gate = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-gate-\(UUID().uuidString)").path
        fixture.model.jobManager.start(kind: .prune, body: { context in
            while !FileManager.default.fileExists(atPath: gate), !context.isCancelled {
                Thread.sleep(forTimeInterval: 0.01)
            }
        })

        #expect(fixture.model.setTartSource(.bundled) == false)
        #expect(fixture.model.activeError?.message
            == "Finish or cancel 1 running job to change the tart source.")
        #expect(fixture.model.settings.tartSource == .installed)
        #expect(fixture.model.chooseCustomTart(path: TartStub(version: "2.40.0").path) == nil)
        #expect(fixture.model.settings.tartCustomPath == nil)

        FileManager.default.createFile(atPath: gate, contents: nil)
        await fixture.model.jobManager.awaitIdle(timeout: 10)
        #expect(fixture.model.setTartSource(.bundled))
        await waitForCheck(fixture.model)
    }

    @Test func runningJobsCountForSettings() async {
        let fixture = makeFixture(bundled: nil, installed: TartStub(version: "2.32.1"))
        #expect(fixture.model.tartJobsRunningCount == 0)
        let gate = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-gate-\(UUID().uuidString)").path
        fixture.model.jobManager.start(kind: .prune, body: { _ in
            while !FileManager.default.fileExists(atPath: gate) { Thread.sleep(forTimeInterval: 0.01) }
        })
        #expect(fixture.model.tartJobsRunningCount == 1)
        FileManager.default.createFile(atPath: gate, contents: nil)
        await fixture.model.jobManager.awaitIdle(timeout: 10)
        #expect(fixture.model.tartJobsRunningCount == 0)
    }

    // MARK: Custom path

    @Test func chooseCustomTartValidates() async {
        let fixture = makeFixture(bundled: nil, installed: TartStub(version: "2.32.1"),
                                  storedSource: .installed)
        await check(fixture.model)
        #expect(fixture.model.chooseCustomTart(path: "/nonexistent/tart")
            == .invalid("/nonexistent/tart", .missing))
        #expect(fixture.model.settings.tartCustomPath == nil)

        let custom = TartStub(version: "2.40.0")
        #expect(fixture.model.chooseCustomTart(path: custom.path) == .valid(custom.path))
        await waitForCheck(fixture.model)
        #expect(fixture.model.settings.tartCustomPath == custom.path)
        #expect(fixture.model.prerequisite?.binaryPath == custom.path)
    }

    @Test func resetCustomTartReturnsToDetection() async {
        let detected = TartStub(version: "2.32.1")
        let fixture = makeFixture(bundled: nil, installed: detected, storedSource: .installed)
        let custom = TartStub(version: "2.40.0")
        fixture.model.settings.tartCustomPath = custom.path
        await check(fixture.model)
        #expect(fixture.model.prerequisite?.binaryPath == custom.path)

        fixture.model.resetCustomTart()
        await waitForCheck(fixture.model)
        #expect(fixture.model.settings.tartCustomPath == nil)
        #expect(fixture.model.prerequisite?.binaryPath == detected.path)
    }

    // MARK: Running VMs and the banner

    @Test func stopAfterSwitchUsesNewBinaryAndSameHome() async {
        let bundled = TartStub(version: "2.41.1")
        let installed = TartStub(version: "2.32.1")
        let fixture = makeFixture(bundled: bundled, installed: installed, storedSource: .installed)
        await check(fixture.model)
        #expect(fixture.model.setTartSource(.bundled))
        await waitForCheck(fixture.model)

        let vm = VMEntry(name: "vm-a", source: "local", running: true, state: "running",
                         diskSize: 50, diskUsage: 10, accessed: nil)
        await fixture.model.stop(vm: vm)

        let lines = await bundled.lines(count: 1)
        #expect(lines == ["stop vm-a TART_HOME=\(fixture.storage)"])
        #expect(await installed.lines(count: 0).isEmpty)
    }

    @Test func bannerSwitchUsesSetTartSource() async throws {
        let fixture = makeFixture(bundled: TartStub(version: "2.41.1"), installed: nil,
                                  storedSource: .installed)
        await check(fixture.model)
        let report = try #require(fixture.model.tartReport)
        #expect(TartPrerequisiteGuidance.guidance(for: report)?.switchTo == .bundled)

        #expect(fixture.model.setTartSource(.bundled))
        await waitForCheck(fixture.model)
        #expect(fixture.model.prerequisite?.isSatisfied == true)
        #expect(fixture.model.tartReport.flatMap(TartPrerequisiteGuidance.guidance(for:)) == nil)
    }
}
