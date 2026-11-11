import Testing
@testable import TartManager

@Suite struct DeleteVMCopyTests {
    @Test func removingTheDiskWarnsAboutAllData() {
        let copy = DeleteVMCopy(removeDisk: true, canKeepDisk: true, keptDisksFolder: "/x/Kept Disks")
        #expect(copy.warning.contains("all of its data"))
        #expect(copy.diskCaption == nil)
    }

    @Test func keepingTheDiskNamesTheFolder() {
        let copy = DeleteVMCopy(removeDisk: false, canKeepDisk: true, keptDisksFolder: "/x/Kept Disks")
        #expect(!copy.warning.contains("all of its data"))
        #expect(copy.diskCaption == "The disk goes to /x/Kept Disks.")
    }

    @Test func stackedVMExplainsThatItsDiskCannotStay() {
        let copy = DeleteVMCopy(removeDisk: false, canKeepDisk: false, keptDisksFolder: "/x/Kept Disks")
        #expect(copy.warning.contains("all of its data"))
        #expect(copy.diskCaption == DeleteVMCopy.cannotKeepCaption)
    }
}
