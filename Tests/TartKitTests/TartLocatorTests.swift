import Testing
import Foundation
@testable import TartKit

@Suite struct TartLocatorTests {
    @Test func findsWellKnownLocationWhenSet() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 5.0.0\n")
        let locator = TartLocator(searchPath: "", wellKnownLocations: [stub])
        #expect(locator.locate() == stub)
    }

    @Test func findsInSearchPath() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 5.0.0\n")
        let dir = (stub as NSString).deletingLastPathComponent
        let locator = TartLocator(searchPath: dir, wellKnownLocations: [])
        #expect(locator.locate() == stub)
    }

    @Test func wellKnownLocationWinsOverSearchPath() {
        let wellKnown = StubBinary.make(script: "#!/bin/sh\necho 5.0.0\n")
        let inPath = StubBinary.make(script: "#!/bin/sh\necho 4.0.0\n")
        let dir = (inPath as NSString).deletingLastPathComponent
        let locator = TartLocator(searchPath: dir, wellKnownLocations: [wellKnown])
        #expect(locator.locate() == wellKnown)
    }
}
