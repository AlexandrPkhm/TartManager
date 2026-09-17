import Testing
@testable import TartKit

@Suite struct TartVersionTests {
    @Test func parsesBareVersion() {
        #expect(TartVersion.parse("2.32.0") == TartVersion(major: 2, minor: 32, patch: 0))
    }

    @Test func parsesWithPrefixAndWhitespace() {
        #expect(TartVersion.parse("tart 2.31.1\n") == TartVersion(major: 2, minor: 31, patch: 1))
    }

    @Test func rejectsGarbage() {
        #expect(TartVersion.parse("not a version") == nil)
        #expect(TartVersion.parse("") == nil)
        #expect(TartVersion.parse("1.2") == nil)
    }

    @Test func ordersVersions() {
        #expect(TartVersion(major: 2, minor: 0, patch: 0) < TartVersion(major: 2, minor: 32, patch: 0))
        #expect(TartVersion(major: 2, minor: 32, patch: 0) < TartVersion(major: 2, minor: 32, patch: 1))
        #expect(TartVersion(major: 3, minor: 0, patch: 0) > TartVersion(major: 2, minor: 99, patch: 9))
        #expect(TartVersion(major: 1, minor: 2, patch: 3) == TartVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func definesMinimumSupportedFloor() {
        #expect(TartVersion.minimumSupported == TartVersion(major: 2, minor: 0, patch: 0))
    }

    @Test func rendersAsDottedTriple() {
        #expect(TartVersion(major: 2, minor: 32, patch: 0).description == "2.32.0")
        #expect("\(TartVersion(major: 1, minor: 9, patch: 9))" == "1.9.9")
    }
}
