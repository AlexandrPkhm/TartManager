import Testing
import Foundation
@testable import TartKit

@Suite struct RunCoordinatorSharesTests {
    @MainActor
    @Test func coordinatorForwardsSharesToTheRunArgv() async throws {
        let (stubPath, invocationFile) = StubBinary.makeRecordingStub(sustainSeconds: 30)
        let coordinator = RunCoordinator()
        let shares = [
            try VMFolderShare.make(name: "work", hostPath: "/Users/me/work",
                                   readOnly: true, customTag: nil),
        ]
        let outcome = await coordinator.launch(
            name: "vm-a", using: TartClient(binaryPath: stubPath),
            shares: shares, earlyFailureWindow: 0.2)
        guard case .started(let handle) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        defer { handle.process.terminate(); handle.process.waitUntilExit() }
        // The stub spawn is not synchronous with `.started`; poll briefly
        // for CONTENT (Issue 4's run test uses the same pattern; existence
        // alone races the shell's `>>` redirection vs. `echo`).
        let deadline = Date().addingTimeInterval(5)
        var invocation = ""
        while invocation.isEmpty, Date() < deadline {
            invocation = (try? String(contentsOfFile: invocationFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if invocation.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(invocation == "run --suspendable --dir work:/Users/me/work:ro vm-a")
    }

    @MainActor
    @Test func coordinatorWithoutSharesKeepsThePrefeatureArgv() async throws {
        let (stubPath, invocationFile) = StubBinary.makeRecordingStub(sustainSeconds: 30)
        let coordinator = RunCoordinator()
        let outcome = await coordinator.launch(
            name: "vm-a", using: TartClient(binaryPath: stubPath),
            earlyFailureWindow: 0.2)
        guard case .started(let handle) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        defer { handle.process.terminate(); handle.process.waitUntilExit() }
        // The stub spawn is not synchronous with `.started`; poll briefly
        // for CONTENT (Issue 4's run test uses the same pattern; existence
        // alone races the shell's `>>` redirection vs. `echo`).
        let deadline = Date().addingTimeInterval(5)
        var invocation = ""
        while invocation.isEmpty, Date() < deadline {
            invocation = (try? String(contentsOfFile: invocationFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if invocation.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(invocation == "run --suspendable vm-a")
    }
}
