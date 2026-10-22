import Testing
import Foundation
@testable import TartKit

@Suite struct BundledTartVerifierTests {
    @Test func unsignedStubIsDamaged() {
        let stub = StubBinary.tartVersionStub(output: "2.41.1")
        guard case .damaged(let reason) = BundledTartVerifier().verify(executablePath: stub) else {
            Issue.record("an unsigned stub must read as damaged")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func missingFileIsDamaged() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)/tart").path
        guard case .damaged = BundledTartVerifier().verify(executablePath: path) else {
            Issue.record("a missing file must read as damaged")
            return
        }
    }

    @Test func wrongTeamIsDamaged() {
        let verifier = BundledTartVerifier(requiredTeamIdentifier: "9M2P8L4D89")
        guard case .damaged(let reason) = verifier.verify(executablePath: "/bin/ls") else {
            Issue.record("an Apple-signed binary must not match the tart team")
            return
        }
        #expect(reason.contains("9M2P8L4D89"))
    }
}
