import Testing
@testable import TartKit
@testable import TartManager

@Suite struct StorageUnavailableCopyTests {
    @Test func missingStorageAsksToMountTheVolume() {
        let copy = StorageUnavailableCopy(reason: .missing)

        #expect(copy.headline == "The folder or its volume can't be found.")
        #expect(copy.hint == "Mount the volume, or choose another folder.")
    }

    @Test func readOnlyStorageAsksToFixPermissions() {
        let copy = StorageUnavailableCopy(reason: .notWritable)

        #expect(copy.headline == "The folder exists, but Tart Manager can't write to it.")
        #expect(copy.hint == "Fix the folder's permissions, or choose another folder.")
    }

    @Test func eachReasonHasDistinctCopy() {
        #expect(StorageUnavailableCopy(reason: .missing) != StorageUnavailableCopy(reason: .notWritable))
    }

    @Test func autoRetryNoteNamesTheRecheckInterval() {
        #expect(StorageUnavailableCopy.autoRetryNote == "Tart Manager checks again every 30 seconds.")
    }
}
