import Testing
@testable import TartManager

@Suite struct DeleteVMCopyTests {
    @Test func removingTheDiskWarnsAboutAllData() {
        let copy = DeleteVMCopy(removeDisk: true, keptDisksFolder: "/x/Kept Disks")
        #expect(copy.warning.contains("all of its data"))
        #expect(copy.keptDiskCaption == nil)
    }

    @Test func keepingTheDiskNamesTheFolder() {
        let copy = DeleteVMCopy(removeDisk: false, keptDisksFolder: "/x/Kept Disks")
        #expect(!copy.warning.contains("all of its data"))
        #expect(copy.keptDiskCaption == "The disk goes to /x/Kept Disks.")
    }
}
