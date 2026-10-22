import Foundation
import os

/// Checks both tart sources: the bundled tart and the installed tart.
///
/// - Bundled: verify the code signature first (no subprocess), then parse
///   `tart --version`. Any failure is `.damaged(.bundled, reason)`.
/// - Installed: a stored custom path is validated with
///   `TartCustomPathValidator` and then run; any failure is
///   `.invalidCustomPath`, never a silent detection. Without a custom path,
///   `TartLocator` detects tart; a failure is `.missing(.installed)`.
///
/// The selected source never falls back to the other one. Every result is
/// logged in `tartRuntime` with its cause, and the user home shown as `~`.
public struct PrerequisiteChecker: Sendable {
    public let bundledExecutablePath: String?
    public let locator: TartLocator
    public let verify: @Sendable (String) -> BundledTartVerification
    public let runner: ProcessRunner
    public let minimumVersion: TartVersion

    public init(bundledExecutablePath: String?,
                locator: TartLocator = TartLocator(),
                verify: @escaping @Sendable (String) -> BundledTartVerification = {
                    BundledTartVerifier().verify(executablePath: $0)
                },
                runner: ProcessRunner = ProcessRunner(),
                minimumVersion: TartVersion = TartVersion.minimumSupported) {
        self.bundledExecutablePath = bundledExecutablePath
        self.locator = locator
        self.verify = verify
        self.runner = runner
        self.minimumVersion = minimumVersion
    }

    /// Synchronous: blocks on up to two subprocesses, each bounded by
    /// `ProcessRunner.defaultTimeout`. Callers must run it off the main actor
    /// (`Task.detached`).
    public func check(preference: TartSourcePreference) -> TartRuntimeReport {
        let report = TartRuntimeReport(
            bundled: checkBundled(),
            installed: checkInstalled(customPath: preference.customPath),
            selected: preference.source ?? .installed,
            storedPreference: preference.source)
        let stored = preference.source?.rawValue ?? "none"
        Logger.tartRuntime.info(
            "selected \(report.selected.rawValue, privacy: .public) (stored: \(stored, privacy: .public))")
        return report
    }

    // MARK: Sources

    private func checkBundled() -> TartPrerequisiteStatus? {
        guard let path = bundledExecutablePath else {
            Logger.tartRuntime.info("bundled: not in this build")
            return nil
        }
        let shownPath = Self.loggable(path)
        if case .damaged(let reason) = verify(path) {
            Logger.tartRuntime.error(
                "bundled: verification failed at \(shownPath, privacy: .public): \(reason, privacy: .public)")
            return .damaged(source: .bundled, reason: reason)
        }
        switch probeVersion(path) {
        case .failure(let failure):
            Logger.tartRuntime.error(
                "bundled: \(failure.reason, privacy: .public) at \(shownPath, privacy: .public)")
            return .damaged(source: .bundled, reason: failure.reason)
        case .success(let version):
            return status(version: version, path: path, source: .bundled)
        }
    }

    private func checkInstalled(customPath: String?) -> TartPrerequisiteStatus {
        if let customPath {
            let shownPath = Self.loggable(customPath)
            if case .invalid(_, let reason) = TartCustomPathValidator.validate(customPath) {
                Logger.tartRuntime.error(
                    "installed: custom path \(shownPath, privacy: .public) is invalid: \(reason.rawValue, privacy: .public)")
                return .invalidCustomPath(path: customPath)
            }
            switch probeVersion(customPath) {
            case .failure(let failure):
                Logger.tartRuntime.error(
                    "installed: custom path \(shownPath, privacy: .public): \(failure.reason, privacy: .public)")
                return .invalidCustomPath(path: customPath)
            case .success(let version):
                return status(version: version, path: customPath, source: .installed)
            }
        }
        guard let path = locator.locate() else {
            Logger.tartRuntime.notice("installed: tart not found")
            return .missing(source: .installed)
        }
        switch probeVersion(path) {
        case .failure(let failure):
            let shownPath = Self.loggable(path)
            Logger.tartRuntime.error(
                "installed: \(failure.reason, privacy: .public) at \(shownPath, privacy: .public)")
            return .missing(source: .installed)
        case .success(let version):
            return status(version: version, path: path, source: .installed)
        }
    }

    private func status(version: TartVersion, path: String, source: TartSource) -> TartPrerequisiteStatus {
        let line = "\(source.rawValue): tart \(version) at \(Self.loggable(path))"
        guard version >= minimumVersion else {
            Logger.tartRuntime.notice("\(line, privacy: .public) is older than \(minimumVersion, privacy: .public)")
            return .outdated(found: version, required: minimumVersion, binaryPath: path, source: source)
        }
        Logger.tartRuntime.info("\(line, privacy: .public)")
        return .ok(version: version, binaryPath: path, source: source)
    }

    // MARK: Version probe

    private struct ProbeFailure: Error {
        let reason: String
    }

    private func probeVersion(_ path: String) -> Result<TartVersion, ProbeFailure> {
        do {
            let result = try runner.run(path, ["--version"])
            guard result.exitCode == 0 else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(ProbeFailure(
                    reason: "tart --version exited \(result.exitCode): \(stderr)"))
            }
            guard let version = TartVersion.parse(result.stdout) else {
                return .failure(ProbeFailure(
                    reason: "tart --version output unparseable: \(result.stdout)"))
            }
            return .success(version)
        } catch {
            return .failure(ProbeFailure(reason: "tart --version run failed: \(error)"))
        }
    }

    /// The path with the user home shown as `~`, for logging.
    static func loggable(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
