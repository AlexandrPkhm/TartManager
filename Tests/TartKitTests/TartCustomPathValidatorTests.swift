import Testing
import Foundation
@testable import TartKit

@Suite struct TartCustomPathValidatorTests {
    private func makeTempDirectory() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func acceptsExecutableStub() {
        let stub = StubBinary.tartVersionStub(output: "2.41.1")
        #expect(TartCustomPathValidator.validate(stub) == .valid(stub))
    }

    @Test func acceptsSymlinkToExecutable() throws {
        let stub = StubBinary.tartVersionStub(output: "2.41.1")
        let link = makeTempDirectory() + "/tart-link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: stub)
        #expect(TartCustomPathValidator.validate(link) == .valid(link))
    }

    @Test func rejectsRelativePath() {
        #expect(TartCustomPathValidator.validate("bin/tart") == .invalid("bin/tart", .notAbsolute))
    }

    @Test func rejectsMissingFile() {
        let path = makeTempDirectory() + "/missing-tart"
        #expect(TartCustomPathValidator.validate(path) == .invalid(path, .missing))
    }

    @Test func rejectsDirectory() {
        let dir = makeTempDirectory()
        #expect(TartCustomPathValidator.validate(dir) == .invalid(dir, .notRegularFile))
    }

    @Test func rejectsNonExecutableFile() throws {
        let path = makeTempDirectory() + "/tart"
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(TartCustomPathValidator.validate(path) == .invalid(path, .notExecutable))
    }
}
