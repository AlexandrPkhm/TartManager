import Testing
@testable import TartManager

@Suite struct SettingsTabTests {
    @Test func everyTabHasItsFrameHeight() {
        #expect(SettingsTab.general.frameHeight == 440)
        #expect(SettingsTab.storage.frameHeight == 620)
        #expect(SettingsTab.about.frameHeight == 320)
    }
}
