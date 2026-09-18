import Testing
import Foundation
@testable import TartKit

@MainActor
@Suite struct CloneJobOutcomeTests {
    func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func completedCloneReportsParsedProgressAndFiresOneStateChange() async {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "14%"
        echo "100%"
        """)
        let manager = JobManager()
        var transitions: [JobInfo] = []
        manager.onStateChange = { transitions.append($0) }
        let job = manager.startClone(source: "golden-vm", to: "vm-from-golden",
                                     using: TartClient(binaryPath: stub))
        #expect(job != nil)
        await manager.awaitIdle(timeout: 2)
        await waitUntil { manager.jobs.first?.progress?.fraction == 1.0 }
        #expect(manager.jobs.first?.phase == .completed)
        #expect(manager.jobs.first?.error == nil)
        // List consistency: exactly one terminal transition reaches the hook
        // AppModel uses to refresh the inventory — no phantom entries.
        #expect(transitions.count == 1)
        #expect(transitions.first?.phase == .completed)
    }

    @Test func failingCloneMarksFailedWithTartsMessage() async {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo 'Error: no space left on device' 1>&2
        exit 9
        """)
        let manager = JobManager()
        var transitions: [JobInfo] = []
        manager.onStateChange = { transitions.append($0) }
        manager.startClone(source: "golden-vm", to: "vm-from-golden",
                           using: TartClient(binaryPath: stub))
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .failed)
        #expect(manager.jobs.first?.error?.message.contains("no space left on device") == true)
        #expect(transitions.first?.phase == .failed)
    }

    @Test func cancelMarksCancelledAndReleasesTheTarget() async {
        let sleepStub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let successStub = StubBinary.make(script: "#!/bin/sh\nexit 0\n")
        let manager = JobManager()
        var transitions: [JobInfo] = []
        manager.onStateChange = { transitions.append($0) }
        let first = manager.startClone(source: "golden-vm", to: "vm-from-golden",
                                       using: TartClient(binaryPath: sleepStub))
        #expect(first != nil)
        try? await Task.sleep(for: .seconds(0.3))
        manager.cancel(id: first!.id)
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .cancelled)
        #expect(manager.jobs.first?.error == nil)
        #expect(transitions.first?.phase == .cancelled)
        // List consistency: the target is fully released — a follow-up clone
        // of the same name starts; the manager holds no phantom reservation.
        let second = manager.startClone(source: "golden-vm", to: "vm-from-golden",
                                        using: TartClient(binaryPath: successStub))
        #expect(second != nil)
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.last?.phase == .completed)
        #expect(manager.jobs.count == 2)
    }
}
