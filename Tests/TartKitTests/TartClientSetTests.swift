import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientSetTests {
    /// Hermetic fixture: a fresh temp dir (removed in `deinit`) holding an
    /// executable stub `tart`. The default script appends each invocation's
    /// argv to an invocation log; `$INVOCATION_FILE` expands to its path.
    final class SetTestFixture {
        let dir: String
        let stubPath: String
        let invocationFile: String

        init(script: String = """
            #!/bin/sh
            echo "$@" >> "$INVOCATION_FILE"
            """) throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            stubPath = dir + "/tart"
            invocationFile = dir + "/invocation.txt"
            let expanded = script
                .replacingOccurrences(of: "$INVOCATION_FILE", with: invocationFile)
            try expanded.write(toFile: stubPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: stubPath)
        }

        func invocations() throws -> [String] {
            try String(contentsOfFile: invocationFile, encoding: .utf8)
                .split(separator: "\n").map(String.init)
        }

        deinit {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    func makeClient(_ fixture: SetTestFixture, timeout: TimeInterval = 10) -> TartClient {
        TartClient(binaryPath: fixture.stubPath, timeout: timeout)
    }

    @Test func fullUpdateSendsAllFlagsInOrder() throws {
        let fixture = try SetTestFixture()
        let client = makeClient(fixture)
        let update = VMResourceUpdate(cpuCount: 4, memoryMB: 8192, diskSizeGB: 80,
                                      display: "1200x800", displayRefit: true)
        try client.set(name: "vm-a", update: update)
        #expect(try fixture.invocations() == [
            "set vm-a --cpu 4 --memory 8192 --disk-size 80 --display 1200x800 --display-refit"])
    }

    @Test func partialUpdateSendsOnlyProvidedFlags() throws {
        let fixture = try SetTestFixture()
        let client = makeClient(fixture)
        try client.set(name: "vm-a",
                       update: VMResourceUpdate(cpuCount: 6, memoryMB: 4096,
                                                diskSizeGB: nil, display: nil, displayRefit: nil))
        #expect(try fixture.invocations() == ["set vm-a --cpu 6 --memory 4096"])
    }

    @Test func unsetRefitSendsNoDisplayFlag() throws {
        // Tri-state refit: nil = not sent — a CPU-only edit must not rewrite
        // the VM's display-refit setting.
        let fixture = try SetTestFixture()
        let client = makeClient(fixture)
        try client.set(name: "vm-a",
                       update: VMResourceUpdate(cpuCount: 4, memoryMB: nil, diskSizeGB: nil,
                                                display: nil, displayRefit: nil))
        #expect(try fixture.invocations() == ["set vm-a --cpu 4"])
    }

    @Test func falseRefitSendsNoDisplayRefitFlag() throws {
        let fixture = try SetTestFixture()
        let client = makeClient(fixture)
        try client.set(name: "vm-a",
                       update: VMResourceUpdate(cpuCount: nil, memoryMB: nil, diskSizeGB: nil,
                                                display: nil, displayRefit: false))
        #expect(try fixture.invocations() == ["set vm-a --no-display-refit"])
    }

    @Test func regenerateMACAndSerialUseIdentityFlags() throws {
        let fixture = try SetTestFixture()
        let client = makeClient(fixture)
        try client.regenerateMAC(name: "vm-a")
        try client.regenerateSerial(name: "vm-a")
        let lines = try fixture.invocations()
        #expect(lines[0] == "set vm-a --random-mac")
        #expect(lines[1] == "set vm-a --random-serial")
    }

    @Test func setFailureThrowsCommandFailed() throws {
        let fixture = try SetTestFixture(script: """
            #!/bin/sh
            echo 'VM is running' 1>&2
            exit 3
            """)
        let client = makeClient(fixture)
        do {
            try client.set(name: "vm-a",
                           update: VMResourceUpdate(cpuCount: 4, memoryMB: nil, diskSizeGB: nil,
                                                    display: nil, displayRefit: nil))
            Issue.record("expected TartClientError.commandFailed")
        } catch let error as TartClientError {
            guard case .commandFailed(let command, let exitCode, _, let stderr) = error else {
                Issue.record("expected .commandFailed, got \(error)")
                return
            }
            #expect(command == "set")
            #expect(exitCode == 3)
            #expect(stderr.contains("VM is running"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func setTimeoutSurfacesAsTypedError() throws {
        // A wedged tart must degrade to a typed error, never disable the
        // editor indefinitely (finding 13, consistent with Issue 3).
        let fixture = try SetTestFixture(script: "#!/bin/sh\nsleep 30\n")
        let client = makeClient(fixture, timeout: 0.5)
        do {
            try client.set(name: "vm-a",
                           update: VMResourceUpdate(cpuCount: 4, memoryMB: nil, diskSizeGB: nil,
                                                    display: nil, displayRefit: nil))
            Issue.record("expected TartClientError.timedOut")
        } catch let error as TartClientError {
            guard case .timedOut = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
