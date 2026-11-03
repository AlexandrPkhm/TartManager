import Testing
import Foundation
@testable import TartKit

@Suite struct DefaultRegistryCatalogTests {
    private func document(schema: Int = 1, images: [(String, String)]) -> Data {
        let entries = images.map { ["label": $0.0, "reference": $0.1] }
        return try! JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "images": entries])
    }

    @Test func builtInListIsAllowedAndHasNoDuplicates() {
        let images = DefaultRegistryCatalog.builtIn
        #expect(images.count == 21)
        #expect(images.allSatisfy(DefaultRegistryCatalog.isAllowed))
        #expect(Set(images.map(\.reference)).count == images.count)
    }

    /// The file that released apps download must stay valid.
    @Test func repositoryFileDecodesWithEveryEntryAllowed() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Catalog/default-registry-images.json")
        let data = try Data(contentsOf: file)
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(raw["images"] as? [[String: String]])
        let images = try DefaultRegistryCatalog.decode(data)
        #expect(images.count == entries.count)
        #expect(Set(images.map(\.reference)).count == images.count)
    }

    @Test func decodeDropsEntriesOutsideTheDefaultRegistry() throws {
        let images = try DefaultRegistryCatalog.decode(document(images: [
            ("Good", "ghcr.io/cirruslabs/macos-tahoe-base:latest"),
            ("Other registry", "evil.example.com/cirruslabs/macos:latest"),
            ("Other organization", "ghcr.io/evil/macos:latest"),
            ("Prefix trick", "ghcr.io/cirruslabs.evil/macos:latest"),
            ("Path trick", "ghcr.io/cirruslabs/../evil/macos:latest"),
            ("Bad characters", "ghcr.io/cirruslabs/macos latest"),
            ("  ", "ghcr.io/cirruslabs/no-label:latest"),
        ]))
        #expect(images.map(\.label) == ["Good"])
    }

    @Test func decodeRejectsUnknownSchemaAndEmptyLists() {
        #expect(throws: DefaultRegistryCatalog.DecodeError.unsupportedSchema(2)) {
            try DefaultRegistryCatalog.decode(document(schema: 2, images: [
                ("Good", "ghcr.io/cirruslabs/macos-tahoe-base:latest"),
            ]))
        }
        #expect(throws: DefaultRegistryCatalog.DecodeError.noUsableImages) {
            try DefaultRegistryCatalog.decode(document(images: []))
        }
        #expect(throws: DefaultRegistryCatalog.DecodeError.noUsableImages) {
            try DefaultRegistryCatalog.decode(document(images: [("Bad", "ghcr.io/evil/macos:latest")]))
        }
        #expect(throws: (any Error).self) {
            try DefaultRegistryCatalog.decode(Data("not json".utf8))
        }
    }
}
