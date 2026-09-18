import Testing
import Foundation
@testable import TartKit

@Suite struct SnapshotRestorePipelineTests {
    /// Records every operation call into a log; failures injected per name.
    final class Recorder {
        let log: ReferenceBox<[String]> = ReferenceBox([])
        var stopFailures: Set<String> = []
        var exportFailures: Set<String> = []
        var deleteFailures: Set<String> = []
        var importFailures: Set<String> = []

        var operations: SnapshotRestorePipeline.Operations {
            SnapshotRestorePipeline.Operations(
                stop: { name in
                    self.log.value.append("stop:\(name)")
                    if self.stopFailures.contains(name) { throw TestError.stop }
                },
                export: { name, path in
                    self.log.value.append("export:\(name):\(path)")
                    if self.exportFailures.contains(name) { throw TestError.export }
                },
                delete: { name in
                    self.log.value.append("delete:\(name)")
                    if self.deleteFailures.contains(name) { throw TestError.delete }
                },
                importArchive: { path, name in
                    self.log.value.append("import:\(path):\(name)")
                    if self.importFailures.contains(name) { throw TestError.import_ }
                })
        }
    }

    struct TestError: Error, Equatable {
        static let stop = TestError()
        static let export = TestError()
        static let delete = TestError()
        static let import_ = TestError()
    }

    final class ReferenceBox<T> { var value: T; init(_ value: T) { self.value = value } }

    @Test func executesAllStepsInOrderWithoutSafety() {
        let recorder = Recorder()
        let outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: "/snap/archive.tvm",
            safetyArchivePath: nil, operations: recorder.operations)
        #expect(outcome == .success)
        #expect(recorder.log.value == [
            "stop:vm-a",
            "delete:vm-a",
            "import:/snap/archive.tvm:vm-a",
        ])
    }

    @Test func executesSafetyExportBetweenStopAndDelete() {
        let recorder = Recorder()
        let outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: "/snap/archive.tvm",
            safetyArchivePath: "/snap/safety.tvm", operations: recorder.operations)
        #expect(outcome == .success)
        #expect(recorder.log.value == [
            "stop:vm-a",
            "export:vm-a:/snap/safety.tvm",
            "delete:vm-a",
            "import:/snap/archive.tvm:vm-a",
        ])
    }

    @Test func stopFailureFailsAtomicallyBeforeAnythingElse() {
        let recorder = Recorder()
        recorder.stopFailures.insert("vm-a")
        let outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: "/snap/archive.tvm",
            safetyArchivePath: "/snap/safety.tvm", operations: recorder.operations)
        guard case .failure(let stage, _) = outcome else {
            Issue.record("expected failure"); return
        }
        #expect(stage == .stop)
        #expect(recorder.log.value == ["stop:vm-a"]) // nothing else ran
    }

    @Test func safetyExportFailureFailsBeforeDelete() {
        let recorder = Recorder()
        recorder.exportFailures.insert("vm-a")
        let outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: "/snap/archive.tvm",
            safetyArchivePath: "/snap/safety.tvm", operations: recorder.operations)
        guard case .failure(.safetyExport, _) = outcome else {
            Issue.record("expected safetyExport"); return
        }
        #expect(recorder.log.value == ["stop:vm-a", "export:vm-a:/snap/safety.tvm"])
        #expect(!recorder.log.value.contains { $0.hasPrefix("delete:") })
    }

    @Test func deleteFailureLeavesVMIntact() {
        let recorder = Recorder()
        recorder.deleteFailures.insert("vm-a")
        let outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: "/snap/archive.tvm",
            safetyArchivePath: nil, operations: recorder.operations)
        guard case .failure(.delete, _) = outcome else {
            Issue.record("expected delete"); return
        }
        #expect(recorder.log.value == ["stop:vm-a", "delete:vm-a"])
        #expect(!recorder.log.value.contains { $0.hasPrefix("import:") })
    }

    /// The Recorder logs the import entry BEFORE throwing, so the log never
    /// ENDS with the delete entry. Assert the ORDER instead — the delete ran
    /// before the failing import.
    @Test func importFailureReportsAfterDeletion() {
        let recorder = Recorder()
        recorder.importFailures.insert("vm-a")
        let archivePath = "/snap/archive.tvm"
        let outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: archivePath,
            safetyArchivePath: nil, operations: recorder.operations)
        guard case .failure(.importArchive, let message) = outcome else {
            Issue.record("expected importArchive"); return
        }
        // The recovery message carries the exact archive path.
        #expect(message.contains(archivePath))
        #expect(message.contains("Import…"))
        let log = recorder.log.value
        guard let deleteIndex = log.firstIndex(of: "delete:vm-a"),
              let importIndex = log.firstIndex(where: { $0.hasPrefix("import:") }) else {
            Issue.record("expected delete and import entries"); return
        }
        // Order, not trailing-suffix — the VM was removed before the
        // failing import ran.
        #expect(deleteIndex < importIndex)
        #expect(log.count == 3)
    }

    /// Every stage failure carries its stage guidance, verbatim — the mapping
    /// is the pure RestoreFailureGuidance, asserted directly.
    @Test func everyStageFailureCarriesItsGuidance() {
        let archivePath = "/snap/a.tvm"

        let stopRecorder = Recorder()
        stopRecorder.stopFailures.insert("vm-a")
        var outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: archivePath,
            safetyArchivePath: nil, operations: stopRecorder.operations)
        guard case .failure(.stop, let stopMessage) = outcome else {
            Issue.record("expected stop"); return
        }
        #expect(stopMessage == RestoreFailureGuidance.message(for: .stop, archivePath: archivePath))
        #expect(stopMessage.contains("nothing was changed"))

        let exportRecorder = Recorder()
        exportRecorder.exportFailures.insert("vm-a")
        outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: archivePath,
            safetyArchivePath: "/snap/s.tvm", operations: exportRecorder.operations)
        guard case .failure(.safetyExport, let exportMessage) = outcome else {
            Issue.record("expected safetyExport"); return
        }
        #expect(exportMessage == RestoreFailureGuidance.message(for: .safetyExport,
                                                                archivePath: archivePath))
        #expect(exportMessage.contains("left untouched"))
        #expect(!exportRecorder.log.value.contains { $0.hasPrefix("delete:") })

        let deleteRecorder = Recorder()
        deleteRecorder.deleteFailures.insert("vm-a")
        outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: archivePath,
            safetyArchivePath: nil, operations: deleteRecorder.operations)
        guard case .failure(.delete, let deleteMessage) = outcome else {
            Issue.record("expected delete"); return
        }
        #expect(deleteMessage == RestoreFailureGuidance.message(for: .delete,
                                                                archivePath: archivePath))

        let importRecorder = Recorder()
        importRecorder.importFailures.insert("vm-a")
        outcome = SnapshotRestorePipeline.restore(
            vmName: "vm-a", archivePath: archivePath,
            safetyArchivePath: nil, operations: importRecorder.operations)
        guard case .failure(.importArchive, let importMessage) = outcome else {
            Issue.record("expected importArchive"); return
        }
        #expect(importMessage == RestoreFailureGuidance.message(for: .importArchive,
                                                                archivePath: archivePath))
    }
}
