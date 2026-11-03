import Testing
import Foundation

/// Runs the real scan script with a stub `curl`, so no test uses the network.
/// The script needs `jq`, which macOS 15 and later include.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/jq")))
struct UpdateRegistryCatalogScriptTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Scripts/update-registry-catalog.sh").path

    /// Page 1 has two known images; `pageTwo` is the stub's shell for page 2.
    private func makeCurl(pageTwo: String) -> String {
        StubBinary.make(named: "curl", script: """
        #!/bin/sh
        case "$*" in
          *"page=1"*)
            echo '<a href="/packages/container/package/macos-a-base"></a>'
            echo '<a href="/packages/container/package/macos-a-xcode"></a>'
            ;;
          *"page=2"*) \(pageTwo) ;;
          *ghcr.io/token*) printf '{"token":"t"}\\n200' ;;
          *tags/list*) echo '{"tags":["latest"]}' ;;
          *) exit 99 ;;
        esac
        """)
    }

    private func makeCatalog(images: [String]) throws -> String {
        let entries = images.map { #"{"label":"\#($0)","reference":"ghcr.io/cirruslabs/\#($0):latest"}"# }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString).json").path
        try #"{"schemaVersion":1,"images":[\#(entries.joined(separator: ","))]}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func run(curl: String, catalog: String) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.script, "--catalog", catalog]
        let curlFolder = (curl as NSString).deletingLastPathComponent
        process.environment = ["PATH": "\(curlFolder):/usr/bin:/bin"]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func references(in catalog: String) throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: catalog))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try #require(object["images"] as? [[String: String]])
        return images.compactMap { $0["reference"] }
    }

    /// The partial result passes the 50% guard, so only the page check can
    /// stop it.
    @Test func failedLaterPageStopsTheScanAndKeepsTheList() throws {
        let catalog = try makeCatalog(images: ["macos-a-base", "macos-a-xcode", "ubuntu"])
        let before = try Data(contentsOf: URL(fileURLWithPath: catalog))
        let result = try run(curl: makeCurl(pageTwo: "exit 22"), catalog: catalog)
        #expect(result.status == 1)
        #expect(result.stderr.contains("could not fetch package page 2"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: catalog)) == before)
    }

    @Test func emptyLaterPageEndsTheScan() throws {
        let catalog = try makeCatalog(images: ["macos-a-base", "macos-a-xcode", "ubuntu"])
        let result = try run(curl: makeCurl(pageTwo: "echo '<html></html>'"), catalog: catalog)
        #expect(result.status == 0)
        #expect(try references(in: catalog) == [
            "ghcr.io/cirruslabs/macos-a-base:latest",
            "ghcr.io/cirruslabs/macos-a-xcode:latest",
        ])
    }

    @Test func largeDropStopsTheScanAndKeepsTheList() throws {
        let catalog = try makeCatalog(images: ["macos-a-base", "macos-a-xcode", "ubuntu", "debian", "fedora"])
        let before = try Data(contentsOf: URL(fileURLWithPath: catalog))
        let result = try run(curl: makeCurl(pageTwo: "echo '<html></html>'"), catalog: catalog)
        #expect(result.status == 1)
        #expect(try Data(contentsOf: URL(fileURLWithPath: catalog)) == before)
    }
}
