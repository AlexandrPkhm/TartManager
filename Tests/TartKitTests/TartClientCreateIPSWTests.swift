import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientCreateIPSWTests {
    @Test func createSendsPathAndDiskSizeAndCompletes() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        let outcome = try client.createFromIPSW(
            name: "vm-a", ipsw: "/Downloads/restore.ipsw", diskSizeGB: 40,
            onOutput: { _ in }, registerCancel: { _ in })
        #expect(outcome == .completed)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "create vm-a --from-ipsw /Downloads/restore.ipsw --disk-size 40")
    }

    @Test func createSendsLatestInPlaceOfPath() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        let outcome = try client.createFromIPSW(
            name: "vm-b", ipsw: "latest", diskSizeGB: 50,
            onOutput: { _ in }, registerCancel: { _ in })
        #expect(outcome == .completed)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "create vm-b --from-ipsw latest --disk-size 50")
    }

    /// The raw cross-version text must reach the analyzer through the
    /// normalized error, even when buried in a long stream (the bounded tail
    /// keeps the final failure lines).
    @Test func failureThrowsNormalizedCommandFailedKeepingTheTail() throws {
        let noise = String(repeating: "restoring x\n", count: 40_000) // > 64 KiB
        let stub = StubBinary.make(script: """
        #!/bin/sh
        printf '%s' "\(noise)" 1>&2
        echo "Failed to start macVM: An error occurred during installation. Installation failed." 1>&2
        exit 4
        """)
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.createFromIPSW(name: "vm-x", ipsw: "latest", diskSizeGB: 50,
                                          onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "create")
            #expect(exitCode == 4)
            #expect(stderr.contains("An error occurred during installation"))
            #expect(stderr.count <= TextAccumulator.maxBufferedCharacters)
        }
    }

    @Test func cancelReturnsCancelled() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub)
        let outcome = try client.createFromIPSW(
            name: "slow-vm", ipsw: "latest", diskSizeGB: 50,
            onOutput: { _ in }) { cancel in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancel() }
            }
        #expect(outcome == .cancelled)
    }

    /// Issue 11's guard, extended to create: user-controlled values are
    /// rejected before any subprocess runs.
    @Test func rejectsLeadingDashNameAndPath() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.createFromIPSW(name: "-vm", ipsw: "latest", diskSizeGB: 50,
                                          onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected commandFailed for the name")
        } catch let TartClientError.commandFailed(command, _, _, stderr) {
            #expect(command == "create")
            #expect(stderr.contains("beginning with '-'"))
        }
        do {
            _ = try client.createFromIPSW(name: "vm", ipsw: "-h.ipsw", diskSizeGB: 50,
                                          onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected commandFailed for the path")
        } catch let TartClientError.commandFailed(command, _, _, stderr) {
            #expect(command == "create")
            #expect(stderr.contains("beginning with '-'"))
        }
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func launchFailureMapsToLaunchFailed() {
        let client = TartClient(binaryPath: "/nonexistent/tart")
        do {
            _ = try client.createFromIPSW(name: "vm", ipsw: "latest", diskSizeGB: 50,
                                          onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected launchFailed")
        } catch let error as TartClientError {
            guard case .launchFailed(let command, _) = error, command == "create" else {
                Issue.record("expected launchFailed(command: \"create\"), got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
