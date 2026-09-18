import Testing
import Foundation
@testable import TartKit

@Suite struct ProcessEnvironmentTests {
    @Test func emptyOverridesYieldNil() {
        // No overrides => nil, so callers leave Process.environment unset
        // and the child inherits the parent environment.
        #expect(ProcessEnvironment.merged(overrides: [:]) == nil)
    }

    @Test func overridesOverlayAndPreserveUnrelatedBaseEntries() {
        let merged = ProcessEnvironment.merged(
            overrides: ["TART_HOME": "/Volumes/SSD/VMs"],
            base: ["PATH": "/bin", "TART_HOME": "/old", "HOME": "/Users/a"])
        #expect(merged?["TART_HOME"] == "/Volumes/SSD/VMs")
        #expect(merged?["PATH"] == "/bin")
        #expect(merged?["HOME"] == "/Users/a")
    }
}
