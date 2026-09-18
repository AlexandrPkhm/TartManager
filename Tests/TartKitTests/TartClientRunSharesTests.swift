import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientRunSharesTests {
    @Test func zeroSharesReproduceThePrefeatureArgv() throws {
        let (stubPath, invocationFile) = StubBinary.makeRecordingStub(sustainSeconds: 30)
        let client = TartClient(binaryPath: stubPath)
        // Deliberately omits `shares` — the default must reproduce Issue 4's
        // exact argv (AC 9).
        let handle = try client.runVM(name: "vm-a", earlyFailureWindow: 0.2)
        defer { handle.process.terminate(); handle.process.waitUntilExit() }
        // The stub spawn is not synchronous with `.started`; poll briefly
        // for the capture (Issue 4's run test uses the same pattern).
        // Wait for CONTENT, not just existence: the shell's `>>` redirection
        // creates the file an instant before `echo` writes it.
        let deadline = Date().addingTimeInterval(5)
        var invocation = ""
        while invocation.isEmpty, Date() < deadline {
            invocation = (try? String(contentsOfFile: invocationFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if invocation.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        }
        #expect(invocation == "run --suspendable vm-a")
    }

    @Test func sharesRenderAsOrderedDirFlags() throws {
        let (stubPath, invocationFile) = StubBinary.makeRecordingStub(sustainSeconds: 30)
        let client = TartClient(binaryPath: stubPath)
        let shares = [
            try VMFolderShare.make(name: "build", hostPath: "/Users/me/src/build",
                                   readOnly: true, customTag: nil),
            try VMFolderShare.make(name: "work", hostPath: "/Users/me/work",
                                   readOnly: false, customTag: "workshare"),
        ]
        let handle = try client.runVM(name: "vm-a", shares: shares, earlyFailureWindow: 0.2)
        defer { handle.process.terminate(); handle.process.waitUntilExit() }
        // The stub spawn is not synchronous with `.started`; poll briefly
        // for the capture (Issue 4's run test uses the same pattern).
        // Wait for CONTENT, not just existence: the shell's `>>` redirection
        // creates the file an instant before `echo` writes it.
        let deadline = Date().addingTimeInterval(5)
        var invocation = ""
        while invocation.isEmpty, Date() < deadline {
            invocation = (try? String(contentsOfFile: invocationFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if invocation.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        }
        #expect(invocation == "run --suspendable "
            + "--dir build:/Users/me/src/build:ro "
            + "--dir work:/Users/me/work:tag=workshare "
            + "vm-a")
    }

    @Test func sharedRunQuickExitStillMapsToCommandFailed() throws {
        // The vanished-host-path failure (AC 7) keeps Issue 4's exact
        // error mapping: the early-window exit carries tart's stderr.
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'directory does not exist' 1>&2\nexit 12\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.runVM(
                name: "vm-a",
                shares: [try VMFolderShare.make(name: "build", hostPath: "/gone",
                                                readOnly: false, customTag: nil)],
                // 3.0 s mirrors Issue 4's quick-exit test: under parallel
                // load, Process exit observation can lag a shorter window,
                // and the poll loop would miss the exit.
                earlyFailureWindow: 3.0)
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "run")
            #expect(exitCode == 12)
            #expect(stderr.contains("directory does not exist"))
        }
    }

    @Test func runVMKeepsTheSharedEarlyFailureWindowDefault() {
        // 4-AFK finding 7: the 5 s window remains the single named constant.
        #expect(DetachedLaunchConfiguration.defaultEarlyFailureWindow == 5)
    }
}
