import Testing
import Foundation
@testable import TartKit

@Suite struct NameValidationTests {
    func entry(_ name: String, source: String = "local") -> VMEntry {
        VMEntry(name: name, source: source, running: false, state: "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    @Test func rejectsNamesStartingWithDash() {
        // finding 11: tart would parse a leading "-" as a flag and exit 0
        // with no VM created — rejected before any subprocess is spawned.
        #expect(!VMNameRules.isValid("--help"))
        #expect(!VMNameRules.isValid("-vm"))
        #expect(!VMNameRules.isValid("-"))
    }

    @Test func acceptsTypicalNames() {
        #expect(VMNameRules.isValid("vm-a"))
        #expect(VMNameRules.isValid("macos26-tahoe"))
        #expect(VMNameRules.isValid("vm_a.1"))
        #expect(VMNameRules.isValid("VM-1"))
    }

    @Test func rejectsNamesOutsideCharacterSet() {
        #expect(!VMNameRules.isValid(""))
        #expect(!VMNameRules.isValid("vm a"))
        #expect(!VMNameRules.isValid("vm/../x"))
        #expect(!VMNameRules.isValid("vm☃"))
        #expect(!VMNameRules.isValid("vm\ttab"))
    }

    @Test func rejectsReferencesStartingWithDash() {
        #expect(!ImageReferenceRules.isValid("--help"))
        #expect(!ImageReferenceRules.isValid("-x"))
    }

    @Test func acceptsTypicalReferences() {
        #expect(ImageReferenceRules.isValid("ghcr.io/cirruslabs/macos-tahoe-base:latest"))
        #expect(ImageReferenceRules.isValid("oci://ghcr.io/cirruslabs/macos-sequoia-base@sha256:abc"))
        #expect(ImageReferenceRules.isValid("my-registry.local:5000/team/image:v1.2"))
    }

    @Test func rejectsReferencesWithWhitespaceOrControlCharacters() {
        #expect(!ImageReferenceRules.isValid(""))
        #expect(!ImageReferenceRules.isValid("ghcr.io/a b"))
        #expect(!ImageReferenceRules.isValid("ghcr.io/a\tb"))
    }

    @Test func availabilityConsidersInventoryAndInFlightTargets() {
        let inventory = VMInventory(from: [entry("vm-a"), entry("img:1", source: "oci")])
        // finding 15: name-uniqueness pre-validation, unit-tested in TartKit.
        #expect(NameAvailability.isAvailable("vm-b", inventory: inventory,
                                             activeJobTargets: []) == true)
        #expect(NameAvailability.isAvailable("vm-a", inventory: inventory,
                                             activeJobTargets: []) == false)
        #expect(NameAvailability.isAvailable("img:1", inventory: inventory,
                                             activeJobTargets: []) == false)
        // finding 4: in-flight job targets make the name unavailable even
        // before tart knows about it.
        #expect(NameAvailability.isAvailable("vm-c", inventory: inventory,
                                             activeJobTargets: ["vm-c"]) == false)
        #expect(NameAvailability.isAvailable("-vm", inventory: inventory,
                                             activeJobTargets: []) == false)
    }

    @Test func availabilityTreatsNilInventoryAsOnlyInFlight() {
        #expect(NameAvailability.isAvailable("vm-x", inventory: nil,
                                             activeJobTargets: []) == true)
        #expect(NameAvailability.isAvailable("vm-x", inventory: nil,
                                             activeJobTargets: ["vm-x"]) == false)
    }
}
