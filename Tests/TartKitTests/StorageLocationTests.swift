import Testing
import Foundation
@testable import TartKit

@Suite struct StorageLocationTests {
    func makeTempDirectory() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func validatesExistingWritableDirectory() {
        let dir = makeTempDirectory()
        #expect(StorageLocationValidator.validate(dir) == .valid(path: dir))
    }

    @Test func rejectsNonexistentPath() throws {
        let missing = makeTempDirectory() + "/nope"
        let result = StorageLocationValidator.validate(missing)
        #expect(result == .invalid(path: missing, reason: "Folder does not exist or is not a folder."))
    }

    @Test func rejectsRegularFile() throws {
        let file = makeTempDirectory() + "/afile"
        try "x".write(toFile: file, atomically: true, encoding: .utf8)
        #expect(StorageLocationValidator.validate(file).isValid == false)
    }

    @Test func rejectsReadOnlyDirectory() throws {
        let dir = makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir) }
        #expect(StorageLocationValidator.validate(dir).isValid == false)
    }

    @Test func availabilityTracksExistenceAndWritability() {
        let dir = makeTempDirectory()
        #expect(StorageLocationValidator.availability(at: dir) == .available(path: dir))
        let missing = dir + "/gone"
        #expect(StorageLocationValidator.availability(at: missing)
                == .unavailable(path: missing, reason: .missing))
        #expect(StorageLocationValidator.availability(at: nil).isAvailable == false)
    }

    @Test func availabilityDetectsReadOnlyLocation() throws {
        // The PRD contract for availability is "mounted/writable": a read-only
        // mount must be unavailable even though the folder exists.
        let dir = makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir) }
        #expect(StorageLocationValidator.availability(at: dir)
                == .unavailable(path: dir, reason: .notWritable))
    }

    @Test func ensureDefaultExistsCreatesMissingDirectoryAndIsIdempotent() throws {
        let dir = makeTempDirectory() + "/nested/default"
        let created = try StorageLocationValidator.ensureDefaultExists(at: dir)
        #expect(created == dir)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(try StorageLocationValidator.ensureDefaultExists(at: dir) == dir)
    }

    @Test func defaultPathIsDotTartUnderHome() {
        #expect(StorageLocationValidator.defaultPath.hasSuffix("/.tart"))
        #expect(StorageLocationValidator.defaultPath.hasPrefix(NSHomeDirectory()))
    }
}
