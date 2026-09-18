import Testing
import Foundation
@testable import TartKit

@Suite struct VMConfigInfoTests {
    /// Captured shape of `tart get --format json` on tart 2.32.0
    /// (Get.swift's VMInfo: capital-first keys, Memory in MB, Display a
    /// string, Size a 3-decimal GB string).
    static let realSchemaJSON = """
    {
      "OS" : "darwin",
      "CPU" : 4,
      "Memory" : 8192,
      "Disk" : 40,
      "DiskFormat" : "raw",
      "Size" : "27.123",
      "Display" : "1024x768",
      "Running" : true,
      "State" : "running"
    }
    """

    @Test func decodesRealSchema() throws {
        let config = try JSONDecoder().decode(VMConfigInfo.self,
                                              from: Data(Self.realSchemaJSON.utf8))
        #expect(config.os == "darwin")
        #expect(config.cpuCount == 4)
        #expect(config.memoryMB == 8192)   // tart already converts bytes -> MB
        #expect(config.diskGB == 40)
        #expect(config.diskFormat == "raw")
        #expect(config.sizeText == "27.123")
        #expect(config.displayText == "1024x768")
        #expect(config.running == true)
        #expect(config.state == "running")
    }

    @Test func displayToleratesUnitSuffix() throws {
        // Real variant: VMDisplayConfig.description appends the unit.
        let config = try JSONDecoder().decode(
            VMConfigInfo.self, from: Data(#"{"Display": "1440x900pt"}"#.utf8))
        #expect(config.displayText == "1440x900pt")
    }

    @Test func toleratesMissingFields() throws {
        let config = try JSONDecoder().decode(VMConfigInfo.self, from: Data("{}".utf8))
        #expect(config.os == nil)
        #expect(config.cpuCount == nil)
        #expect(config.memoryMB == nil)
        #expect(config.diskGB == nil)
        #expect(config.diskFormat == nil)
        #expect(config.sizeText == nil)
        #expect(config.displayText == nil)
        #expect(config.running == nil)
        #expect(config.state == nil)
    }

    @Test func wrongTypedFieldsDecodeAsNil() throws {
        // Defensive contract: a schema drift degrades fields, not the pane.
        let json = #"{"CPU": "four", "Memory": "lots", "Display": 123}"#
        let config = try JSONDecoder().decode(VMConfigInfo.self, from: Data(json.utf8))
        #expect(config.cpuCount == nil)
        #expect(config.memoryMB == nil)
        #expect(config.displayText == nil)
    }
}
