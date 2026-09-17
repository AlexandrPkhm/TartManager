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
}
