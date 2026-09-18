import Testing
import Foundation
@testable import TartKit

@Suite struct PartialImportCleanupTests {
    static func entry(name: String = "partial-junk", accessed: Date?) -> VMEntry {
        VMEntry(name: name, source: "local", running: false, state: "stopped",
                diskSize: 64, diskUsage: 10, accessed: accessed)
    }

    @Test func decideClassifiesEntriesByJobWindow() {
        let started = Date(timeIntervalSince1970: 1_000)
        let ended = Date(timeIntervalSince1970: 1_100)
        #expect(PartialImportCleanup.decide(entries: [], name: "partial-junk",
                                            jobStartedAt: started, jobEndedAt: ended) == .nothingToDo)
        #expect(PartialImportCleanup.decide(entries: [Self.entry(accessed: Date(timeIntervalSince1970: 900))],
                                            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended)
                    == .conflictPreserved)
        #expect(PartialImportCleanup.decide(entries: [Self.entry(accessed: Date(timeIntervalSince1970: 1_200))],
                                            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended)
                    == .conflictPreserved)
        #expect(PartialImportCleanup.decide(entries: [Self.entry(accessed: nil)],
                                            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended)
                    == .conflictPreserved)
        #expect(PartialImportCleanup.decide(entries: [Self.entry(accessed: Date(timeIntervalSince1970: 1_050))],
                                            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended)
                    == .artifact)
        #expect(PartialImportCleanup.decide(entries: [Self.entry(accessed: started)],
                                            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended)
                    == .artifact)
        #expect(PartialImportCleanup.decide(entries: [Self.entry(accessed: ended)],
                                            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended)
                    == .artifact)
    }

    @Test func performDeletesArtifactInsideWindow() {
        let started = Date(timeIntervalSince1970: 1_000)
        let ended = Date(timeIntervalSince1970: 1_100)
        var deleted: [String] = []
        let result = PartialImportCleanup.perform(
            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended,
            list: { [Self.entry(accessed: Date(timeIntervalSince1970: 1_050))] },
            delete: { deleted.append($0) },
            onFailure: { _ in Issue.record("unexpected failure surfaced") })
        #expect(result == .deleted)
        #expect(deleted == ["partial-junk"])
    }

    @Test func performPreservesEntryOutsideWindowAndSurfacesNotice() {
        let started = Date(timeIntervalSince1970: 1_000)
        let ended = Date(timeIntervalSince1970: 1_100)
        var deleted: [String] = []
        var failures: [TartClientError] = []
        let result = PartialImportCleanup.perform(
            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended,
            list: { [Self.entry(accessed: Date(timeIntervalSince1970: 900))] },
            delete: { deleted.append($0) },
            onFailure: { failures.append($0) })
        #expect(result == .preserved)
        #expect(deleted.isEmpty)
        #expect(failures.count == 1)
        if case let .commandFailed(command, _, _, stderr) = failures[0] {
            #expect(command == "import-cleanup")
            #expect(stderr.contains("left untouched"))
        } else {
            Issue.record("expected a commandFailed preservation notice")
        }
    }

    @Test func performSurfacesListFailureWithoutDeleting() {
        var deleted: [String] = []
        var failures: [TartClientError] = []
        let listError = TartClientError.commandFailed(command: "list", exitCode: 2,
                                                      stdout: "", stderr: "storage unavailable")
        let result = PartialImportCleanup.perform(
            name: "partial-junk",
            jobStartedAt: Date(timeIntervalSince1970: 1_000),
            jobEndedAt: Date(timeIntervalSince1970: 1_100),
            list: { throw listError },
            delete: { deleted.append($0) },
            onFailure: { failures.append($0) })
        #expect(result == .listFailed)
        #expect(deleted.isEmpty)
        #expect(failures == [listError])
    }

    @Test func performSurfacesDeleteFailure() {
        var failures: [TartClientError] = []
        let deleteError = TartClientError.commandFailed(command: "delete", exitCode: 3,
                                                        stdout: "", stderr: "cannot delete")
        let result = PartialImportCleanup.perform(
            name: "partial-junk",
            jobStartedAt: Date(timeIntervalSince1970: 1_000),
            jobEndedAt: Date(timeIntervalSince1970: 1_100),
            list: { [Self.entry(accessed: Date(timeIntervalSince1970: 1_050))] },
            delete: { _ in throw deleteError },
            onFailure: { failures.append($0) })
        #expect(result == .deleteFailed)
        #expect(failures == [deleteError])
    }
}
