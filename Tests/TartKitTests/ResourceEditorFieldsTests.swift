import Testing
import Foundation
@testable import TartKit

@Suite struct ResourceEditorFieldsTests {
    @Test func parsesTrimmedTextsIntoUpdate() {
        let fields = ResourceEditorFields(cpuText: " 4 ", memoryText: " 8192 ",
                                          diskText: " 80 ", displayText: " 1200x800 ",
                                          displayRefit: true)
        let update = fields.update
        #expect(update.cpuCount == 4)
        #expect(update.memoryMB == 8192)
        #expect(update.diskSizeGB == 80)
        #expect(update.display == "1200x800")
        #expect(update.displayRefit == true)
    }

    @Test func emptyFieldsProduceEmptyUpdate() {
        let fields = ResourceEditorFields(cpuText: "", memoryText: "", diskText: "",
                                          displayText: "   ", displayRefit: nil)
        #expect(fields.update.isEmpty)
        #expect(fields.isEmpty)
    }

    @Test func refitTriStatePassesThrough() {
        let fit = ResourceEditorFields(displayRefit: true)
        let fixed = ResourceEditorFields(displayRefit: false)
        let untouched = ResourceEditorFields(displayRefit: nil)
        #expect(fit.update.arguments == ["--display-refit"])
        #expect(fixed.update.arguments == ["--no-display-refit"])
        #expect(untouched.update.arguments.isEmpty)
    }

    @Test func malformedTextMapsToNilNotSent() {
        // Documented invariant: AppModel.apply runs the validator before
        // building the update, so this nil-mapping is never sent silently.
        let fields = ResourceEditorFields(cpuText: "abc", memoryText: "1.5",
                                          diskText: "twelve", displayText: "big")
        #expect(fields.update.cpuCount == nil)
        #expect(fields.update.memoryMB == nil)
        #expect(fields.update.diskSizeGB == nil)
        #expect(fields.update.display == "big") // display passes through; validator rejects it
    }
}
