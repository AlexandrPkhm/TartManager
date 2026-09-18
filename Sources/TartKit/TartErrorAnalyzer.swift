import Foundation
import os

/// Normalized failure payload presented to the user and carried by jobs.
public struct TartOperationError: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let operation: String
    public let message: String
    public let rawDetails: String
    public let hint: String?
    /// Structured exit code for logging and tickets; nil for non-command
    /// failures (launchFailed/timedOut/decodingFailed) and preconditions.
    public let exitCode: Int32?

    public init(id: UUID = UUID(), operation: String, message: String,
                rawDetails: String, hint: String? = nil, exitCode: Int32? = nil) {
        self.id = id
        self.operation = operation
        self.message = message
        self.rawDetails = rawDetails
        self.hint = hint
        self.exitCode = exitCode
    }

    /// Deterministic, complete report for the clipboard or bug tickets.
    public func copyReport() -> String {
        var lines = [
            "Tart Manager error report",
            "operation: \(operation)",
            "exit code: \(exitCode.map(String.init) ?? "unknown")",
        ]
        if let hint {
            lines.append("hint: \(hint)")
        }
        lines.append("message: \(message)")
        lines.append(rawDetails)
        return lines.joined(separator: "\n")
    }
}

/// Pure normalization of raw CLI failures into user-presentable payloads.
public enum TartErrorAnalyzer {
    /// The known Apple cross-version restore failure signature. Public: the
    /// IPSW-creation slice references it from the app target.
    public static let crossVersionSignature = "An error occurred during installation"

    /// Explanatory hint for the same-host-version requirement, rendered by
    /// the standard sheet when `crossVersionSignature` matches.
    public static let crossVersionHint = """
        Apple's Virtualization.framework can only restore a macOS version whose \
        major version matches the host. Use a prebuilt image (for example a \
        Cirrus Labs OCI image) instead of installing this IPSW on this Mac.
        """

    /// Explanatory hint for suspend failures: only VMs started with the
    /// suspend-capable configuration (which Tart Manager always uses) can
    /// be suspended. Attached to *any* suspend failure, not pattern-matched:
    /// the refusal text diverges across tart versions (Research).
    public static let suspendHint = """
        Suspend only works for VMs started with the suspend-capable \
        configuration (tart's `--suspendable` run flag), which Tart Manager \
        always uses. This VM was most likely started outside Tart Manager \
        without it — stop it here, then run it from Tart Manager. (VMs in \
        the suspend-capable configuration have guest audio disabled.)
        """

    /// Capture budget per stream for `rawDetails`: a verbose multi-GB failure
    /// must not be duplicated in memory on the failure path.
    public static let maxCapturedCharactersPerStream = 65_536

    public static func analyze(command: String, exitCode: Int32,
                               stdout: String, stderr: String,
                               redact: @Sendable (String) -> String = { $0 }) -> TartOperationError {
        // Scrub first: message, raw details, and the copy payload are all
        // built from the scrubbed text.
        let cleanStderr = redact(stderr)
        let cleanStdout = redact(stdout)

        let firstLine = cleanStderr
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map { $0.trimmingCharacters(in: .whitespaces) }
        var message = firstLine.map {
            $0.hasPrefix("Error: ") ? String($0.dropFirst("Error: ".count)) : $0
        } ?? ""
        if message.isEmpty {
            message = "tart exited with code \(exitCode)"
        }

        let rawDetails = """
        command: \(command)
        exit code: \(exitCode)
        --- stderr ---
        \(cappedCapture(cleanStderr))
        --- stdout ---
        \(cappedCapture(cleanStdout))
        """

        var hint: String?
        if cleanStderr.contains(crossVersionSignature) {
            hint = crossVersionHint
        } else if command == "suspend" {
            hint = suspendHint
        } else {
            // Drift fallback: if tart rewords the signature the hint stops
            // firing silently by design — this debug line makes the miss
            // visible in unified logging so a reworded message can be
            // re-captured as a new golden fixture.
            Logger.errorReporting.debug(
                "cross-version signature not matched for \(command, privacy: .public)")
        }

        return TartOperationError(
            operation: command, message: message, rawDetails: rawDetails,
            hint: hint, exitCode: exitCode)
    }

    /// Normalize any client failure. `redact` is the gate for
    /// credential-touching operations before they route through the
    /// standard sheet.
    public static func analyze(_ error: TartClientError,
                               redact: @Sendable (String) -> String = { $0 }) -> TartOperationError {
        switch error {
        case let .commandFailed(command, exitCode, stdout, stderr):
            return analyze(command: command, exitCode: exitCode,
                           stdout: stdout, stderr: stderr, redact: redact)
        case let .launchFailed(command, executable):
            return TartOperationError(
                operation: command,
                message: "tart could not be launched (\(executable))",
                rawDetails: "command: \(command)\nexecutable: \(executable)")
        case let .timedOut(command, timeout):
            return TartOperationError(
                operation: command,
                message: "tart timed out after \(Int(timeout)) s",
                rawDetails: "command: \(command)\ntimeout: \(Int(timeout)) s")
        case let .decodingFailed(command, output):
            return TartOperationError(
                operation: command,
                message: "tart returned output the app could not parse",
                rawDetails: "command: \(command)\n--- output ---\n\(cappedCapture(redact(output)))")
        case let .stdinDeliveryFailed(command):
            return TartOperationError(
                operation: command,
                message: "tart did not read the credentials the app sent",
                rawDetails: "command: \(command)\nstdin was not accepted (the child exited before reading it)")
        }
    }

    /// Caps one stream for `rawDetails`: small outputs stay verbatim, an
    /// oversized stream keeps its head plus a truncation marker.
    static func cappedCapture(_ text: String) -> String {
        guard text.count > maxCapturedCharactersPerStream else { return text }
        let dropped = text.count - maxCapturedCharactersPerStream
        return String(text.prefix(maxCapturedCharactersPerStream))
            + "\n… truncated \(dropped) more characters (capture limit)"
    }
}

public extension TartClientError {
    /// Single choke point for failure normalization: app code presents
    /// `rawError.normalized` and never calls `TartErrorAnalyzer` directly.
    var normalized: TartOperationError { TartErrorAnalyzer.analyze(self) }

    /// The redacting form of the choke point for credential-touching
    /// operations: the scrubber is applied before the message, raw details,
    /// and copy payload are built.
    func normalized(redact: @escaping @Sendable (String) -> String) -> TartOperationError {
        TartErrorAnalyzer.analyze(self, redact: redact)
    }
}
