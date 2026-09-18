import Testing
import Foundation
@testable import TartKit

@Suite struct SnapshotStoreTests {
    func makeStore() -> (store: SnapshotStore, directory: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return (SnapshotStore(directory: dir.path), dir.path)
    }

    func touch(_ path: String, size: Int = 128) {
        FileManager.default.createFile(atPath: path, contents: Data(count: size))
    }

    @Test func proposePathSanitizesAndTimestamps() {
        let (store, _) = makeStore()
        let date = Date(timeIntervalSince1970: 0)
        let path = store.proposeArchivePath(vmName: "my vm:2", label: "Clean s.tate!", date: date)
        // finding 2: disallowed characters are REPLACED with "-", not stripped.
        #expect(path.hasPrefix(store.directory + "/my-vm-2__"))
        #expect(path.hasSuffix(".tvm"))
        let bare = store.proposeArchivePath(vmName: "vm", label: nil, date: date)
        #expect(bare.contains("__unnamed"))
    }

    @Test func proposePathNeverCollidesWithExistingArchives() {
        // finding 9: same-second/same-label snapshots must never overwrite.
        let (store, directory) = makeStore()
        let date = Date(timeIntervalSince1970: 0)
        let first = store.proposeArchivePath(vmName: "vm", label: "pre", date: date)
        touch(first)
        let second = store.proposeArchivePath(vmName: "vm", label: "pre", date: date)
        #expect(second != first)
        #expect(second.hasSuffix("-1.tvm"))
        #expect(!FileManager.default.fileExists(atPath: second))
    }

    @Test func proposePathFallsBackForUnsanitizableNames() {
        let (store, _) = makeStore()
        let path = store.proposeArchivePath(vmName: " :/", label: nil,
                                            date: Date(timeIntervalSince1970: 0))
        #expect((path as NSString).lastPathComponent.hasPrefix("vm__"))
    }

    @Test func metadataRoundTripsThroughTheScan() throws {
        let (store, directory) = makeStore()
        let archivePath = store.proposeArchivePath(vmName: "vm-a", label: "pre-experiment")
        touch(archivePath, size: 256)
        let created = Date(timeIntervalSince1970: 1_000_000)
        try store.writeMetadata(archivePath: archivePath, vmName: "vm-a",
                                 label: "pre-experiment", createdAt: created)

        let snapshots = try store.snapshots()
        #expect(snapshots.count == 1)
        let snapshot = snapshots[0]
        #expect(snapshot.vmName == "vm-a")
        #expect(snapshot.label == "pre-experiment")
        #expect(snapshot.archivePath == archivePath)
        #expect(snapshot.id == archivePath) // finding 5: id IS the archive path
        #expect(snapshot.sizeBytes == 256)
        #expect(abs(snapshot.createdAt!.timeIntervalSince1970 - 1_000_000) < 1)

        #expect(try store.snapshots(forVM: "vm-a").count == 1)
        #expect(try store.snapshots(forVM: "other").isEmpty)
    }

    @Test func foreignArchivesDegradeGracefully() throws {
        let (store, directory) = makeStore()
        touch(directory + "/mystery.tvm", size: 64)
        let snapshots = try store.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].label == "mystery")
        #expect(snapshots[0].vmName == "unknown")
        #expect(snapshots[0].createdAt != nil) // falls back to the file's modification date
    }

    @Test func partialArchiveWithoutSidecarIsUnownedNotInvisible() throws {
        // finding 7: a partial .tvm IS seen by the scan — as an unowned
        // foreign entry that never matches the owning VM's name.
        let (store, directory) = makeStore()
        touch(directory + "/vm-a__20260101-000000__partial.tvm", size: 64)
        let snapshots = try store.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].vmName == "unknown")
        #expect(try store.snapshots(forVM: "vm-a").isEmpty)
    }

    @Test func scanOrdersNewestFirst() throws {
        let (store, _) = makeStore()
        let older = store.proposeArchivePath(vmName: "vm", label: nil,
                                             date: Date(timeIntervalSince1970: 100))
        let newer = store.proposeArchivePath(vmName: "vm", label: nil,
                                             date: Date(timeIntervalSince1970: 200))
        touch(older); touch(newer)
        try store.writeMetadata(archivePath: older, vmName: "vm", label: nil,
                                createdAt: Date(timeIntervalSince1970: 100))
        try store.writeMetadata(archivePath: newer, vmName: "vm", label: nil,
                                createdAt: Date(timeIntervalSince1970: 200))
        let snapshots = try store.snapshots(forVM: "vm")
        #expect(snapshots.map(\.archivePath) == [newer, older])
    }

    @Test func missingFolderYieldsEmptyCatalog() throws {
        let store = SnapshotStore(directory: "/nonexistent/snapshots")
        #expect(try store.snapshots().isEmpty)
    }

    @Test func sidecarsDoNotAppearAsArchives() throws {
        let (store, _) = makeStore()
        let path = store.proposeArchivePath(vmName: "vm", label: nil)
        touch(path, size: 32)
        try store.writeMetadata(archivePath: path, vmName: "vm", label: nil,
                                createdAt: Date())
        #expect(try store.snapshots().count == 1)
    }

    @Test func scanIsMemoizedUntilTheFolderChanges() throws {
        // finding 6: an unchanged folder is served from cache, not re-scanned;
        // a sidecar write invalidates the cache.
        let (store, directory) = makeStore()
        let path = store.proposeArchivePath(vmName: "vm", label: nil)
        touch(path, size: 32)
        try store.writeMetadata(archivePath: path, vmName: "vm", label: nil,
                                createdAt: Date())
        _ = try store.snapshots()
        #expect(store.scanCount == 1)
        _ = try store.snapshots()
        #expect(store.scanCount == 1)          // memoized: no per-archive work
        touch(directory + "/extra.tvm", size: 8) // folder changed
        _ = try store.snapshots()
        #expect(store.scanCount == 2)          // re-scanned
    }

    @Test func deleteRemovesArchiveAndSidecar() throws {
        let (store, _) = makeStore()
        let path = store.proposeArchivePath(vmName: "vm", label: nil)
        touch(path, size: 32)
        try store.writeMetadata(archivePath: path, vmName: "vm", label: nil, createdAt: Date())
        #expect(try store.snapshots().count == 1)

        try store.delete(Snapshot(vmName: "vm", label: nil, createdAt: nil,
                                  archivePath: path, sizeBytes: 0))
        #expect(try store.snapshots().isEmpty)          // archive gone
        #expect(!FileManager.default.fileExists(atPath: path + ".meta.json")) // sidecar gone
    }

    @Test func deleteVanishedArchiveIsSilentNoOp() throws {
        let (store, _) = makeStore()
        let ghost = Snapshot(vmName: "vm", label: nil, createdAt: nil,
                             archivePath: "/nonexistent/x.tvm", sizeBytes: 0)
        try store.delete(ghost) // must not throw — reconciliation is the scan's job
        #expect(try store.snapshots().isEmpty)
    }

    /// If the ARCHIVE cannot be removed, the sidecar must survive so the next
    /// scan still owns the snapshot (it never degrades to an unowned entry).
    @Test func deleteFailurePreservesSidecarMetadata() throws {
        let (store, directory) = makeStore()
        let path = store.proposeArchivePath(vmName: "vm", label: nil)
        touch(path, size: 32)
        try store.writeMetadata(archivePath: path, vmName: "vm", label: nil, createdAt: Date())

        // Make the folder read-only so archive removal fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                              ofItemAtPath: directory)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: directory)
        }
        #expect(throws: (any Error).self) {
            try store.delete(Snapshot(vmName: "vm", label: nil, createdAt: nil,
                                      archivePath: path, sizeBytes: 0))
        }
        #expect(FileManager.default.fileExists(atPath: path + ".meta.json"))
        let snapshots = try store.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].vmName == "vm") // still owned — metadata intact
    }

    /// The delete invalidates the memoized catalog: the list reflects the
    /// removal immediately, not on the next folder change.
    @Test func deleteInvalidatesTheMemoizedCatalog() throws {
        let (store, _) = makeStore()
        let path = store.proposeArchivePath(vmName: "vm", label: nil)
        touch(path, size: 32)
        try store.writeMetadata(archivePath: path, vmName: "vm", label: nil, createdAt: Date())
        _ = try store.snapshots()
        #expect(store.scanCount == 1)      // primed the memo cache

        try store.delete(Snapshot(vmName: "vm", label: nil, createdAt: nil,
                                  archivePath: path, sizeBytes: 0))
        #expect(try store.snapshots().isEmpty)
        #expect(store.scanCount == 2)      // cache invalidated by delete
    }
}
