import Foundation

/// Validation failures for registry operations, thrown before any subprocess
/// runs so an empty field or a hostile host can never reach the CLI as argv.
/// Normalizes to the standard sheet payload with no fabricated exit code —
/// `exitCode` stays nil.
public enum RegistryArgumentError: Error, Equatable, Sendable {
    case emptyField(command: String, field: String)
    case invalidHost(command: String, reason: String)

    /// Presentation payload built from the validation itself.
    public var normalized: TartOperationError {
        switch self {
        case .emptyField(let command, let field):
            return TartOperationError(
                operation: command,
                message: "The \(field) must not be empty.",
                rawDetails: "\(command) was not run: the \(field) field was empty.")
        case .invalidHost(let command, let reason):
            return TartOperationError(
                operation: command,
                message: "Invalid registry host: \(reason)",
                rawDetails: "\(command) was not run: \(reason)")
        }
    }
}

/// Registry input validation. Pure and total over any string.
public enum RegistryCredentialRules {
    /// Validates a login: host, username, and password must all be present
    /// and well-formed. Throws `RegistryArgumentError` — never a silent no-op.
    public static func validate(host: String,
                                username: String? = nil,
                                password: String? = nil,
                                command: String) throws {
        if let username {
            guard !username.isEmpty else {
                throw RegistryArgumentError.emptyField(command: command, field: "username")
            }
        }
        if let password {
            guard !password.isEmpty else {
                throw RegistryArgumentError.emptyField(command: command, field: "password")
            }
        }
        try validateHost(host, command: command)
    }

    /// A host is usable only when it is non-empty, does not start with `-`
    /// (flag injection via tart's swift-argument-parser), and contains no
    /// whitespace or control characters.
    public static func validateHost(_ host: String, command: String) throws {
        guard !host.isEmpty else {
            throw RegistryArgumentError.emptyField(command: command, field: "host")
        }
        guard !host.hasPrefix("-") else {
            throw RegistryArgumentError.invalidHost(
                command: command, reason: "the host must not start with “-”")
        }
        let forbidden = host.unicodeScalars.first { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
        }
        guard forbidden == nil else {
            throw RegistryArgumentError.invalidHost(
                command: command, reason: "the host must not contain spaces or control characters")
        }
    }

    /// Predicate the Registries section renders inline: the view only
    /// renders results of pure TartKit functions.
    public static func isValidHost(_ host: String) -> Bool {
        (try? validateHost(host, command: "login")) != nil
    }
}

/// Scrubs credential values out of failure text before it reaches the error
/// sheet, the clipboard, or the log.
public enum RegistryCredentialScrubber {
    /// The replacement for every occurrence of the secret and its encodings.
    public static let replacement = "******"

    /// Builds the `redact:` hook for `TartClientError.normalized(redact:)`:
    /// removes the exact secret and its base64 encoding. The closure captures
    /// the secret for the duration of one operation only.
    public static func redactor(secret: String) -> @Sendable (String) -> String {
        let encodings = [secret, Data(secret.utf8).base64EncodedString()]
            .filter { !$0.isEmpty }
        return { text in
            encodings.reduce(text) { partial, encoding in
                partial.replacingOccurrences(of: encoding, with: replacement)
            }
        }
    }

    /// Scrub `text` once, replacing every occurrence of `secret` and its
    /// base64 encoding.
    public static func scrub(_ text: String, secret: String) -> String {
        redactor(secret: secret)(text)
    }
}
