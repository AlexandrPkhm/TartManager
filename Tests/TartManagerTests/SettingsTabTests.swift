import Testing
@testable import TartManager

@Suite struct SettingsTabTests {
    @Test func everyTabHasItsFrameHeight() {
        #expect(SettingsTab.general.frameHeight == 740)
        #expect(SettingsTab.storage.frameHeight == 514)
        #expect(SettingsTab.about.frameHeight == 320)
    }
}
