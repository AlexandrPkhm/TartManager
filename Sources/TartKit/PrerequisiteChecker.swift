import Foundation
import os

/// Checks the tart prerequisite: locate the binary, parse `tart --version`, compare.
///
/// Every collapse into `.missing` logs its distinct cause (not found, non-zero
/// exit, unparseable output, run failure) so an installed-but-broken tart is
/// diagnosable even though the public status enum stays `.missing`.
public struct PrerequisiteChecker: Sendable {
    public let locator: TartLocator
    public let runner: ProcessRunner
    public let minimumVersion: TartVersion

    private static let logger = Logger(
        subsystem: "org.tartmanager.TartKit", category: "PrerequisiteChecker")

    public init(locator: TartLocator = TartLocator(),
                runner: ProcessRunner = ProcessRunner(),
                minimumVersion: TartVersion = TartVersion.minimumSupported) {
        self.locator = locator
        self.runner = runner
        self.minimumVersion = minimumVersion
    }

    /// Synchronous: blocks on the subprocess, bounded by
    /// `ProcessRunner.defaultTimeout`. Callers must run it off the main
    /// actor (`Task.detached`) — see Task 7.
    public func check() -> TartPrerequisiteStatus {
        guard let binaryPath = locator.locate() else {
            Self.logger.notice("tart binary not found; reporting .missing")
            return .missing
        }
        do {
            let result = try runner.run(binaryPath, ["--version"])
            guard result.exitCode == 0 else {
                Self.logger.error(
                    "tart --version exited \(result.exitCode, privacy: .public); stdout=\(result.stdout, privacy: .public); stderr=\(result.stderr, privacy: .public); reporting .missing")
                return .missing
            }
            guard let version = TartVersion.parse(result.stdout) else {
                Self.logger.error(
                    "tart --version output unparseable: \(result.stdout, privacy: .public); reporting .missing")
                return .missing
            }
            if version < minimumVersion {
                return .outdated(found: version, required: minimumVersion, binaryPath: binaryPath)
            }
            return .ok(version: version, binaryPath: binaryPath)
        } catch {
            Self.logger.error(
                "tart --version run failed: \(String(describing: error), privacy: .public); reporting .missing")
            return .missing
        }
    }
}
