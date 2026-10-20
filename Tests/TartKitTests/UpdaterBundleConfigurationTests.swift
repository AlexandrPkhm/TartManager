import Testing
@testable import TartKit

@Suite struct UpdaterBundleConfigurationTests {
    @Test func completeDictionaryHasNoMissingKeys() {
        let info: [String: Any] = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "key",
        ]
        #expect(UpdaterBundleConfiguration.missingKeys(in: info).isEmpty)
    }

    @Test func emptyDictionaryReportsBothKeys() {
        #expect(UpdaterBundleConfiguration.missingKeys(in: [:]) == ["SUFeedURL", "SUPublicEDKey"])
    }

    @Test func nilDictionaryReportsBothKeys() {
        #expect(UpdaterBundleConfiguration.missingKeys(in: nil) == ["SUFeedURL", "SUPublicEDKey"])
    }

    @Test func blankValueCountsAsMissing() {
        let info: [String: Any] = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "",
        ]
        #expect(UpdaterBundleConfiguration.missingKeys(in: info) == ["SUPublicEDKey"])
    }

    @Test func nonStringValueCountsAsMissing() {
        let info: [String: Any] = ["SUFeedURL": 42, "SUPublicEDKey": "key"]
        #expect(UpdaterBundleConfiguration.missingKeys(in: info) == ["SUFeedURL"])
    }
}
