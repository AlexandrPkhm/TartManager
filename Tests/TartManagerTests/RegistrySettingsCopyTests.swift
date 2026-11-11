import Testing
@testable import TartKit
@testable import TartManager

@Suite struct RegistrySettingsCopyTests {
    @Test func modeLabelsMatchThePanel() {
        #expect(RegistrySettingsCopy.modeLabel(.standard) == "Default")
        #expect(RegistrySettingsCopy.modeLabel(.custom) == "Custom")
    }

    @Test func pullCaptionNamesTheRegistryAndTheNextStep() {
        #expect(RegistrySettingsCopy.pullCaption.contains("ghcr.io/cirruslabs"))
        #expect(RegistrySettingsCopy.pullCaption.contains("Images page"))
    }
}
