import Testing
import Foundation
@testable import TartKit

@Suite struct VMEntryDecodingTests {
    static let goldenJSON = """
    [
      {
        "Running" : false,
        "Source" : "local",
        "Size" : 0,
        "Accessed" : "2026-09-17T08:19:30Z",
        "Disk" : 35,
        "Name" : "fake-vm",
        "State" : "stopped"
      },
      {
        "Running" : true,
        "Source" : "oci",
        "Size" : 27.5,
        "Name" : "ghcr.io/cirruslabs/macos-tahoe-base:latest",
        "State" : "running"
      }
    ]
    """

    func decode(_ json: String) throws -> [VMEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VMEntry].self, from: Data(json.utf8))
    }

    @Test func decodesCapturedShape() throws {
        let entries = try decode(Self.goldenJSON)
        #expect(entries.count == 2)

        let local = entries[0]
        #expect(local.name == "fake-vm")
        #expect(local.source == "local")
        #expect(local.running == false)
        #expect(local.state == "stopped")
        #expect(local.diskSize == 35)
        #expect(local.diskUsage == 0)
        #expect(local.accessed != nil)
        #expect(local.isLocal)

        let image = entries[1]
        #expect(image.name == "ghcr.io/cirruslabs/macos-tahoe-base:latest")
        #expect(!image.isLocal)
        #expect(image.running)
        #expect(image.state == "running")
        #expect(image.diskUsage == 27.5)
        #expect(image.accessed == nil)
    }

    @Test func decodesEmptyArrayAsEmpty() throws {
        #expect(try decode("[\n\n]") == [])
        #expect(try decode("[]") == [])
    }

    @Test func toleratesMissingOptionalFields() throws {
        let entries = try decode(#"[{"Name": "x", "Source": "local"}]"#)
        #expect(entries[0].running == false)
        #expect(entries[0].state == "")
        #expect(entries[0].diskSize == 0)
        #expect(entries[0].diskUsage == 0)
        #expect(entries[0].accessed == nil)
    }

    @Test func rejectsUndefinedRows() {
        #expect(throws: DecodingError.self) { _ = try decode(#"[{}]"#) }
        #expect(throws: DecodingError.self) { _ = try decode(#"{"Name":"x"}"#) }
    }
}
