import Foundation

/// Polls a stub's capture file until it holds the lines a test expects.
///
/// A stub writes `echo … >> file`: the shell creates the file before `echo`
/// writes the line, so waiting only for the file to exist can read it empty
/// under load. These helpers wait for `count` complete (newline-terminated)
/// lines or the deadline, then return every complete line so the caller
/// keeps its exact assertions.
enum CaptureFile {
    /// Blocks the calling thread; for synchronous tests.
    static func waitForLines(
        atPath path: String, count: Int, timeout: TimeInterval = 5
    ) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var lines = completeLines(atPath: path)
        while lines.count < count, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            lines = completeLines(atPath: path)
        }
        return lines
    }

    /// Suspends between polls; for `async` tests, including `@MainActor` ones.
    static func waitForLines(
        atPath path: String, count: Int, timeout: TimeInterval = 5
    ) async throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var lines = completeLines(atPath: path)
        while lines.count < count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            lines = completeLines(atPath: path)
        }
        return lines
    }

    /// The newline-terminated lines in the file; a missing file and a
    /// partially written last line both count as not yet written.
    private static func completeLines(atPath path: String) -> [String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        var lines = content.components(separatedBy: "\n")
        lines.removeLast() // the text after the last newline is incomplete
        return lines
    }
}
