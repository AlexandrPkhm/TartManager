import Foundation
import Testing
@testable import TartKit

@Suite struct WorkspaceSelectionTests {
    private func vm(_ name: String, running: Bool = false) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped", diskSize: 50, diskUsage: 12, accessed: nil)
    }

    @Test func restoresByNameAndUsesFreshLifecycleState() {
        let fresh = vm("second", running: true)
        #expect(WorkspaceSelection.resolve(preferredName: "second", localVMs: [vm("first"), fresh]) == fresh)
    }

    @Test func missingSelectionFallsBackAndEmptyInventoryClears() {
        #expect(WorkspaceSelection.resolve(preferredName: "deleted", localVMs: [vm("first")]) == vm("first"))
        #expect(WorkspaceSelection.resolve(preferredName: "deleted", localVMs: []) == nil)
    }

    @Test func imageDisplayPreservesExactReferenceAndRegistryPort() {
        let reference = "registry.example:5000/team/macos:latest"
        let display = OCIImageDisplay(reference: reference)
        #expect(display.reference == reference)
        #expect(display.repository == "registry.example:5000/team/macos")
        #expect(display.name == "macos")
        #expect(display.version == "latest")
        #expect(!display.isDigest)
        let digest = OCIImageDisplay(reference: "ghcr.io/team/macos@sha256:abcdef")
        #expect(digest.name == "macos")
        #expect(digest.version == "sha256:abcdef")
        #expect(digest.isDigest)
        #expect(OCIImageDisplay(reference: "registry.example:5000/team/macos").version == nil)
    }
}
