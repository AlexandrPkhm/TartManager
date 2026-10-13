import Foundation
import Darwin
import Testing
@testable import TartKit

@Suite struct VMRunSessionTests {
    @Test func recognizesOnlyAnExplicitRunFlag() {
        #expect(VMRunSession.isSuspendable(arguments: ["tart", "run", "--suspendable", "My VM"]) == true)
        #expect(VMRunSession.isSuspendable(arguments: ["tart", "run", "My VM", "--suspendable"]) == true)
        #expect(VMRunSession.isSuspendable(arguments: ["tart", "run", "My VM"]) == false)
        #expect(VMRunSession.isSuspendable(arguments: ["tart", "run", "--", "--suspendable"]) == false)
        #expect(VMRunSession.isSuspendable(arguments: ["tart", "run", "--dir=--suspendable", "vm"]) == false)
        #expect(VMRunSession.isSuspendable(arguments: ["tart", "list", "--suspendable"]) == nil)
        #expect(VMRunSession.isSuspendable(arguments: []) == nil)
    }

    @Test func decodesArgvWithoutSearchingEnvironmentOrExecutablePath() {
        var count: Int32 = 3
        var data = withUnsafeBytes(of: &count) { Data($0) }
        data.append(Data("/tmp/--suspendable/tart\0\0tart\0run\0vm\0FLAG=--suspendable\0".utf8))
        #expect(VMRunSession.decodeArguments(data) == ["tart", "run", "vm"])
        #expect(VMRunSession.decodeArguments(Data()) == nil)
        #expect(VMRunSession.decodeArguments(data.prefix(12)) == nil)
    }

    @Test func readsNativeProcessArguments() {
        #expect(VMRunSession.arguments(pid: getpid()) == CommandLine.arguments)
    }

    @Test func missingOrUnlockedConfigIsUnknown() throws {
        let root = VMStorageFixture.make(storageWithVM: "vm", os: "darwin")
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(VMRunSession.read(atVMDirectory: root + "/vms/missing") == nil)
        #expect(VMRunSession.read(atVMDirectory: root + "/vms/vm") == nil)
    }

    /// A real child owns tart's lock shape. Compiling this tiny helper with
    /// the project's macOS toolchain avoids requiring tart, a VM, or Python.
    @MainActor
    @Test func liveSessionTracksExternalLaunchRestartAndExit() async throws {
        let root = VMStorageFixture.make(storageWithVM: "My VM", os: "darwin")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let directory = root + "/vms/My VM"
        let source = root + "/session.c"
        let executable = root + "/tart"
        try """
        #include <fcntl.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <unistd.h>
        int main(void) {
            int fd = open(getenv("SESSION_CONFIG"), O_RDWR);
            struct flock lock = {0};
            lock.l_type = F_WRLCK;
            lock.l_whence = SEEK_SET;
            if (fd < 0 || fcntl(fd, F_SETLK, &lock) != 0) return 1;
            FILE *ready = fopen(getenv("SESSION_READY"), "w");
            if (!ready) return 2;
            fclose(ready);
            getchar();
            close(fd);
            return 0;
        }
        """.write(toFile: source, atomically: true, encoding: .utf8)
        let compile = try ProcessRunner().run("/usr/bin/cc", [source, "-o", executable])
        try #require(compile.exitCode == 0, "\(compile.stderr)")
        let stub = StubBinary.make(script: "#!/bin/sh\necho '[{\"Name\":\"My VM\",\"Source\":\"local\",\"Running\":true,\"State\":\"running\"}]'\n")
        for suspendable in [true, false] {
            let ready = root + "/ready-\(suspendable)"
            let child = Process()
            let input = Pipe()
            child.executableURL = URL(fileURLWithPath: executable)
            child.arguments = ["run"] + (suspendable ? ["--suspendable"] : []) + ["My VM"]
            child.environment = ["SESSION_CONFIG": directory + "/config.json", "SESSION_READY": ready]
            child.standardInput = input
            try child.run()
            defer {
                if child.isRunning { child.terminate() }
                child.waitUntilExit()
            }
            let deadline = Date().addingTimeInterval(5)
            while !FileManager.default.fileExists(atPath: ready), child.isRunning, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(FileManager.default.fileExists(atPath: ready))
            // Fresh clients model reopening the manager while the VM stays alive.
            for _ in 0..<2 {
                let client = TartClient(binaryPath: stub, environment: ["TART_HOME": root])
                #expect(try client.list()[0].canSuspend == suspendable)
                #expect(client.canSuspend(name: "My VM") == suspendable)
            }
            try input.fileHandleForWriting.close()
            child.waitUntilExit()
            #expect(child.terminationStatus == 0)
            #expect(VMRunSession.read(atVMDirectory: directory) == nil)
        }
    }
}
