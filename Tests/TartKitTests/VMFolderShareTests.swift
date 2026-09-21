import Testing
import Foundation
@testable import TartKit

@Suite struct VMFolderShareTests {
    @Test func dirArgumentRendersNamePathAndNoOptions() {
        let share = try! VMFolderShare.make(name: "build", hostPath: "/Users/me/src/build",
                                             readOnly: false, customTag: nil)
        #expect(share.dirArgument == "build:/Users/me/src/build")
    }

    @Test func dirArgumentRendersReadOnly() throws {
        let share = try VMFolderShare.make(name: "sources", hostPath: "/Users/me/src/sources",
                                            readOnly: true, customTag: nil)
        #expect(share.dirArgument == "sources:/Users/me/src/sources:ro")
    }

    @Test func dirArgumentRendersTagAloneAndCombinedWithReadOnly() throws {
        let tagged = try VMFolderShare.make(name: "work", hostPath: "/Users/me/work",
                                            readOnly: false, customTag: "workshare")
        #expect(tagged.dirArgument == "work:/Users/me/work:tag=workshare")

        let both = try VMFolderShare.make(name: "work", hostPath: "/Users/me/work",
                                          readOnly: true, customTag: "workshare")
        #expect(both.dirArgument == "work:/Users/me/work:ro,tag=workshare")
    }

    @Test func defaultNameIsSanitizedFolderName() throws {
        let share = try VMFolderShare.makeDefault(hostPath: "/Users/me/My Build Folder")
        #expect(share.name == "My Build Folder")
        #expect(share.dirArgument.hasPrefix("My Build Folder:/Users/me/My Build Folder"))
    }

    @Test func mountNamePreservesInternalSpacesAndTrimsOuterWhitespace() throws {
        var share = try VMFolderShare.make(name: "  Host Downloads  ",
                                           hostPath: "/Users/me/Downloads",
                                           readOnly: false, customTag: nil)
        #expect(share.name == "Host Downloads")
        #expect(share.dirArgument == "Host Downloads:/Users/me/Downloads")

        share.set(name: "Host   Downloads")
        #expect(share.name == "Host   Downloads")
        share.set(name: "Host: Downloads, Archive")
        #expect(share.name == "Host Downloads Archive")
        #expect(share.isValidForPersistence)
    }

    @Test func customTagStillMapsSpacesToHyphens() throws {
        var share = try VMFolderShare.make(name: "Host Downloads",
                                           hostPath: "/Users/me/Downloads",
                                           readOnly: false, customTag: nil)
        share.set(customTag: "Host Downloads")
        #expect(share.customTag == "Host-Downloads")
        #expect(share.dirArgument == "Host Downloads:/Users/me/Downloads:tag=Host-Downloads")
    }

    @Test func validationRejectsBadNamesTagsAndPaths() {
        #expect(throws: VMFolderShareError.self) {
            _ = try VMFolderShare.make(name: "", hostPath: "/x", readOnly: false, customTag: nil)
        }
        #expect(throws: VMFolderShareError.self) {
            _ = try VMFolderShare.make(name: "bad:name", hostPath: "/x", readOnly: false, customTag: nil)
        }
        #expect(throws: VMFolderShareError.self) {
            _ = try VMFolderShare.make(name: "ok", hostPath: "/path:with:colons",
                                       readOnly: false, customTag: nil)
        }
        #expect(throws: VMFolderShareError.self) {
            _ = try VMFolderShare.make(name: "ok", hostPath: "/x", readOnly: false, customTag: "a,b")
        }
    }

    // Edit path (finding 5): the row bindings route through these mutating
    // methods, so the same charset rules hold for typed input.

    @Test func setNameStripsAmbiguityCharsAndPreservesSpaces() throws {
        var share = try VMFolderShare.make(name: "work", hostPath: "/Users/me/work",
                                           readOnly: false, customTag: nil)
        share.set(name: "My Work")
        #expect(share.name == "My Work")
        share.set(name: "bad:name")
        #expect(share.name == "badname")
        share.set(name: "x,y&z!")
        #expect(share.name == "xyz")
        #expect(share.isValidForPersistence)
    }

    @Test func setCustomTagStripsAndClearsOnEmpty() throws {
        var share = try VMFolderShare.make(name: "work", hostPath: "/Users/me/work",
                                           readOnly: false, customTag: nil)
        share.set(customTag: "my tag")
        #expect(share.customTag == "my-tag")
        share.set(customTag: "a,b")
        #expect(share.customTag == "ab")
        share.set(customTag: "   ")
        #expect(share.customTag == nil)
        #expect(share.isValidForPersistence)
    }

    @Test func persistenceValidityRejectsAmbiguousValues() {
        let badName = VMFolderShare(name: "bad:name", hostPath: "/x", readOnly: false, customTag: nil)
        #expect(!badName.isValidForPersistence)
        let badTag = VMFolderShare(name: "ok", hostPath: "/x", readOnly: false, customTag: "a,b")
        #expect(!badTag.isValidForPersistence)
        let emptyName = VMFolderShare(name: "", hostPath: "/x", readOnly: false, customTag: nil)
        #expect(!emptyName.isValidForPersistence)
        let good = VMFolderShare(name: "ok", hostPath: "/x", readOnly: false, customTag: "t")
        #expect(good.isValidForPersistence)
    }

    @Test func codableRoundTrips() throws {
        let share = try VMFolderShare.make(name: "build", hostPath: "/Users/me/src/build",
                                           readOnly: true, customTag: "b")
        let data = try JSONEncoder().encode([share])
        let decoded = try JSONDecoder().decode([VMFolderShare].self, from: data)
        #expect(decoded == [share])
    }
}
