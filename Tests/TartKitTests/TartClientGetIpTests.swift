import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientGetIpTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    @Test func getParsesConfigJsonAndSendsRightArgs() throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let configJSON = #"{"OS":"darwin","CPU":4,"Memory":8192,"Disk":40,"DiskFormat":"raw","Size":"27.123","Display":"1024x768"}"#
        let fixturePath = dir.appendingPathComponent("config.json").path
        try configJSON.write(toFile: fixturePath, atomically: true, encoding: .utf8)
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        cat "\(fixturePath)"
        """)
        let client = TartClient(binaryPath: stub)
        let config = try client.get(name: "vm-a")
        #expect(config.cpuCount == 4)
        #expect(config.memoryMB == 8192)
        #expect(config.displayText == "1024x768")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "get vm-a --format json")
    }

    @Test func getFailureThrowsCommandFailed() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'VM not found' 1>&2\nexit 2\n")
        let client = TartClient(binaryPath: stub)
        #expect(throws: TartClientError.self) { _ = try client.get(name: "ghost") }
    }

    @Test func getTimeoutThrowsTimedOut() {
        // get/ip must run under TartClient's deadline, never hang.
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub, timeout: 0.5)
        do {
            _ = try client.get(name: "hang")
            Issue.record("expected .timedOut")
        } catch let TartClientError.timedOut(command, _) {
            // The merged client maps the runner's full command line through
            // (same convention as the list timeout test).
            #expect(command.contains("get hang --format json"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func ipSendsRightArgsAndTrimsOutput() throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        printf '192.168.64.7\n'
        """)
        let client = TartClient(binaryPath: stub)
        #expect(try client.ip(name: "vm-a") == "192.168.64.7")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "ip vm-a")   // the ip argv itself is asserted
    }

    @Test func ipReturnsNilOnFailure() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nexit 1\n")
        let client = TartClient(binaryPath: stub)
        #expect(try client.ip(name: "vm-a") == nil)
    }

    @Test func ipReturnsNilOnEmptyOutput() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nprintf '\\n'\n")
        let client = TartClient(binaryPath: stub)
        #expect(try client.ip(name: "vm-a") == nil)
    }
}
