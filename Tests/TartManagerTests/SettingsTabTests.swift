import Testing
@testable import TartManager

@Suite struct SettingsTabTests {
    @Test func everyTabHasItsFrameHeight() {
        #expect(SettingsTab.general.frameHeight == 514)
        #expect(SettingsTab.storage.frameHeight == 514)
        #expect(SettingsTab.about.frameHeight == 471)
    }

    @Test func generalMatchesStorage() {
        #expect(SettingsTab.general.frameHeight == SettingsTab.storage.frameHeight)
    }
}
