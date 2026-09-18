import Testing
import Foundation
@testable import TartKit

@Suite struct VMRenameTests {
    func entry(_ name: String, state: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running, state: state,
                diskSize: 50, diskUsage: 50, accessed: nil)
    }

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var listQueue: [Result<[VMEntry], TartClientError>] = []
        var renameCalls: [(from: String, to: String)] = []
        var renameError: TartClientError?

        func enqueueList(_ call: Result<[VMEntry], TartClientError>) {
            lock.lock(); defer { lock.unlock() }
            listQueue.append(call)
        }

        func popList() -> Result<[VMEntry], TartClientError> {
            lock.lock(); defer { lock.unlock() }
            return listQueue.isEmpty ? .success([]) : listQueue.removeFirst()
        }
    }

    func makeOps(_ recorder: Recorder) -> VMRename.Ops {
        VMRename.Ops(
            list: { try recorder.popList().get() },
            rename: { from, to in
                recorder.renameCalls.append((from, to))
                if let error = recorder.renameError { throw error }
            })
    }

    @Test func freeTargetRenamesAndReturnsRenamed() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        let outcome = try VMRename.perform(from: "vm-a", to: "vm-b", ops: makeOps(recorder))
        #expect(outcome == .renamed)
        #expect(recorder.renameCalls.count == 1)
        #expect(recorder.renameCalls[0].from == "vm-a")
        #expect(recorder.renameCalls[0].to == "vm-b")
    }

    @Test func occupiedTargetIsRefusedBeforeSpawn() throws {
        // The issue's mandated uniqueness validation: the target exists on a
        // fresh list → refusal, and the rename op is never invoked.
        let recorder = Recorder()
        recorder.enqueueList(.success([
            entry("vm-a", state: "stopped", running: false),
            entry("vm-b", state: "stopped", running: false),
        ]))
        do {
            _ = try VMRename.perform(from: "vm-a", to: "vm-b", ops: makeOps(recorder))
            Issue.record("expected refusal")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "rename")
            #expect(exitCode == -1)
            #expect(stderr.contains("already exists"))
        }
        #expect(recorder.renameCalls.isEmpty)
    }

    @Test func runningOrSuspendedSourceIsRefusedBeforeSpawn() throws {
        for fixture in [entry("vm-a", state: "running", running: true),
                        entry("vm-a", state: "suspended", running: false)] {
            let recorder = Recorder()
            recorder.enqueueList(.success([fixture]))
            do {
                _ = try VMRename.perform(from: "vm-a", to: "vm-b", ops: makeOps(recorder))
                Issue.record("expected refusal for \(fixture.state)")
            } catch let TartClientError.commandFailed(_, exitCode, _, stderr) {
                #expect(exitCode == -1)
                #expect(stderr.contains("Stop the VM first"))
            }
            #expect(recorder.renameCalls.isEmpty)
        }
    }

    @Test func absentSourceIsACleanNoOp() throws {
        // Race tolerance: the VM vanished (deleted externally) — logged
        // no-op, no false error; the list refresh reconciles.
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        let outcome = try VMRename.perform(from: "vm-a", to: "vm-b", ops: makeOps(recorder))
        #expect(outcome == .sourceVanished)
        #expect(recorder.renameCalls.isEmpty)
    }

    @Test func renameFailurePropagates() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        let original = TartClientError.commandFailed(command: "rename", exitCode: 2,
                                                     stdout: "", stderr: "name taken at CLI level")
        recorder.renameError = original
        do {
            _ = try VMRename.perform(from: "vm-a", to: "vm-b", ops: makeOps(recorder))
            Issue.record("expected rethrow")
        } catch let TartClientError.commandFailed(_, exitCode, _, stderr) {
            #expect(exitCode == 2)
            #expect(stderr.contains("name taken at CLI level"))
        }
    }
}
