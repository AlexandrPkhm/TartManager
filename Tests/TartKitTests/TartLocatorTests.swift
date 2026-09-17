import Testing
import Foundation
@testable import TartKit

@Suite struct TartLocatorTests {
    @Test func prefersExplicitExecutablePath() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 5.0.0\n")
        let locator = TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: [])
        #expect(locator.locate() == stub)
    }

    @Test func ignoresNonExecutableExplicitPathAndFindsNothingElsewhere() {
        let locator = TartLocator(explicitPath: "/nonexistent/tart", searchPath: "", wellKnownLocations: [])
        #expect(locator.locate() == nil)
    }

    @Test func findsWellKnownLocationWhenSet() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 5.0.0\n")
        let locator = TartLocator(explicitPath: nil, searchPath: "", wellKnownLocations: [stub])
        #expect(locator.locate() == stub)
    }

    @Test func findsInSearchPath() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 5.0.0\n")
        let dir = (stub as NSString).deletingLastPathComponent
        let locator = TartLocator(explicitPath: nil, searchPath: dir, wellKnownLocations: [])
        #expect(locator.locate() == stub)
    }
}
