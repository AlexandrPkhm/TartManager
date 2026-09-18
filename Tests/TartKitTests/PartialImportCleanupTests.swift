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
        let deleted = LockedValue<[String]>([])
        let result = PartialImportCleanup.perform(
            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended,
            list: { [Self.entry(accessed: Date(timeIntervalSince1970: 1_050))] },
            delete: { name in deleted.withValue { $0.append(name) } },
            onFailure: { _ in Issue.record("unexpected failure surfaced") })
        #expect(result == .deleted)
        #expect(deleted.value == ["partial-junk"])
    }

    @Test func performPreservesEntryOutsideWindowAndSurfacesNotice() {
        let started = Date(timeIntervalSince1970: 1_000)
        let ended = Date(timeIntervalSince1970: 1_100)
        let deleted = LockedValue<[String]>([])
        let failures = LockedValue<[TartClientError]>([])
        let result = PartialImportCleanup.perform(
            name: "partial-junk", jobStartedAt: started, jobEndedAt: ended,
            list: { [Self.entry(accessed: Date(timeIntervalSince1970: 900))] },
            delete: { name in deleted.withValue { $0.append(name) } },
            onFailure: { failure in failures.withValue { $0.append(failure) } })
        #expect(result == .preserved)
        #expect(deleted.value.isEmpty)
        #expect(failures.value.count == 1)
        if case let .commandFailed(command, _, _, stderr) = failures.value[0] {
            #expect(command == "import-cleanup")
            #expect(stderr.contains("left untouched"))
        } else {
            Issue.record("expected a commandFailed preservation notice")
        }
    }

    @Test func performSurfacesListFailureWithoutDeleting() {
        let deleted = LockedValue<[String]>([])
        let failures = LockedValue<[TartClientError]>([])
        let listError = TartClientError.commandFailed(command: "list", exitCode: 2,
                                                      stdout: "", stderr: "storage unavailable")
        let result = PartialImportCleanup.perform(
            name: "partial-junk",
            jobStartedAt: Date(timeIntervalSince1970: 1_000),
            jobEndedAt: Date(timeIntervalSince1970: 1_100),
            list: { throw listError },
            delete: { name in deleted.withValue { $0.append(name) } },
            onFailure: { failure in failures.withValue { $0.append(failure) } })
        #expect(result == .listFailed)
        #expect(deleted.value.isEmpty)
        #expect(failures.value == [listError])
    }

    @Test func performSurfacesDeleteFailure() {
        let failures = LockedValue<[TartClientError]>([])
        let deleteError = TartClientError.commandFailed(command: "delete", exitCode: 3,
                                                        stdout: "", stderr: "cannot delete")
        let result = PartialImportCleanup.perform(
            name: "partial-junk",
            jobStartedAt: Date(timeIntervalSince1970: 1_000),
            jobEndedAt: Date(timeIntervalSince1970: 1_100),
            list: { [Self.entry(accessed: Date(timeIntervalSince1970: 1_050))] },
            delete: { _ in throw deleteError },
            onFailure: { failure in failures.withValue { $0.append(failure) } })
        #expect(result == .deleteFailed)
        #expect(failures.value == [deleteError])
    }
}
