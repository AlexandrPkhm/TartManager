import Testing
import Foundation
@testable import TartKit

@Suite struct VMGuestOSTests {
    func makeVMDirectory(config: String?) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        if let config {
            try! config.write(toFile: dir.appendingPathComponent("config.json").path,
                              atomically: true, encoding: .utf8)
        }
        return dir.path
    }

    @Test func readsTheGuestOSFromConfigJSON() {
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: #"{"os":"darwin"}"#)) == "darwin")
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: #"{"os":"linux"}"#)) == "linux")
    }

    @Test func missingMalformedOrKeylessConfigYieldsNil() {
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: nil)) == nil)
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: "not json")) == nil)
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: #"[1,2,3]"#)) == nil)
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: #"{"cpuCount":4}"#)) == nil)
        #expect(VMGuestOS.read(atVMDirectory: makeVMDirectory(config: #"{"os":42}"#)) == nil)
        #expect(VMGuestOS.read(atVMDirectory: "/definitely/missing-vm") == nil)
    }

    /// The single predicate behind both the `--suspendable` run flag and the
    /// Suspend affordances: tart 2.32 refuses everything but macOS.
    @Test func onlyDarwinSupportsSuspend() {
        #expect(VMGuestOS.supportsSuspend("darwin"))
        #expect(VMGuestOS.supportsSuspend("Darwin"))
        #expect(!VMGuestOS.supportsSuspend("linux"))
        #expect(!VMGuestOS.supportsSuspend("windows"))
        #expect(!VMGuestOS.supportsSuspend(nil))
        #expect(!VMGuestOS.supportsSuspend(""))
    }
}
