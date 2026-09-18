import Foundation

/// Shared stub-binary scaffolding for TartKit tests.
///
/// Every test that needs a fake `tart` executable goes through here, so the
/// temp-dir + chmod scaffolding lives in exactly one place as the CLI surface
/// grows across slices.
enum StubBinary {
    /// Writes `script` into a fresh temp directory as an executable file
    /// named `name` (default `tart`) and returns its absolute path.
    static func make(named name: String = "tart", script: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try! script.write(toFile: path, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// A fake `tart` that prints `output` for `--version` and stays silent
    /// (exits 0) for any other invocation.
    static func tartVersionStub(output: String) -> String {
        make(script: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then printf '%s' "\(output)"; fi
            """)
    }

    /// Writes a `tart` stub that appends `"$@"` to `invocation.txt` in its own
    /// temp directory and exits 0. `sustainSeconds > 0` appends a `sleep`
    /// before the exit so detached-launch tests (early-failure window) can
    /// use the same helper; the default keeps the original behavior.
    static func makeRecordingStub(sustainSeconds: Int = 0) -> (stubPath: String, invocationFile: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stubPath = dir.appendingPathComponent("tart").path
        let sustain = sustainSeconds > 0 ? "sleep \(sustainSeconds)\n" : ""
        let script = """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        \(sustain)exit 0
        """
        try! script.write(toFile: stubPath, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubPath)
        return (stubPath, invocationFile)
    }

    /// Recording stub with stdin capture — the `--password-stdin` pattern:
    /// appends argv to `invocation.txt`, captures everything it
    /// reads from stdin (until EOF) to `stdin.txt`, and exits 0. One shared
    /// fixture for every argv/stdin test in this slice.
    static func makeRecordingStubWithStdinCapture() -> (stubPath: String, invocationFile: String, stdinFile: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stdinFile = dir.appendingPathComponent("stdin.txt").path
        let stubPath = dir.appendingPathComponent("tart").path
        let script = """
        #!/bin/sh
        echo "$@" > "\(invocationFile)"
        cat > "\(stdinFile)"
        exit 0
        """
        try! script.write(toFile: stubPath, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubPath)
        return (stubPath, invocationFile, stdinFile)
    }
}
