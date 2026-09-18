import Testing
import Foundation
@testable import TartKit

@Suite struct RegistryCredentialTests {
    @Test func validationAcceptsCleanInputs() throws {
        try RegistryCredentialRules.validate(host: "ghcr.io", username: "ci-bot",
                                             password: "tok-1", command: "login")
        try RegistryCredentialRules.validate(host: "registry.example.com:5000", command: "logout")
        #expect(RegistryCredentialRules.isValidHost("ghcr.io"))
        #expect(RegistryCredentialRules.isValidHost("registry.example.com:5000"))
    }

    @Test func validationRejectsEmptyFieldsWithTheFieldName() {
        func emptyField(command: String, _ body: () throws -> Void) -> String? {
            do {
                try body()
                Issue.record("expected RegistryArgumentError")
                return nil
            } catch let error as RegistryArgumentError {
                guard case .emptyField(let thrownCommand, let field) = error,
                      thrownCommand == command else {
                    Issue.record("expected emptyField(command: \(command)), got \(error)")
                    return nil
                }
                return field
            } catch {
                Issue.record("expected RegistryArgumentError, got \(error)")
                return nil
            }
        }

        #expect(emptyField(command: "login") {
            try RegistryCredentialRules.validate(host: "", username: "u", password: "p", command: "login")
        } == "host")
        #expect(emptyField(command: "login") {
            try RegistryCredentialRules.validate(host: "ghcr.io", username: "", password: "p", command: "login")
        } == "username")
        #expect(emptyField(command: "login") {
            try RegistryCredentialRules.validate(host: "ghcr.io", username: "u", password: "", command: "login")
        } == "password")
    }

    @Test func validationRejectsHostileHosts() {
        func invalidHostReason(_ host: String, command: String = "login") -> String? {
            do {
                try RegistryCredentialRules.validateHost(host, command: command)
                Issue.record("expected RegistryArgumentError")
                return nil
            } catch let error as RegistryArgumentError {
                guard case .invalidHost(let thrownCommand, let reason) = error,
                      thrownCommand == command else {
                    Issue.record("expected invalidHost(command: \(command)), got \(error)")
                    return nil
                }
                return reason
            } catch {
                Issue.record("expected RegistryArgumentError, got \(error)")
                return nil
            }
        }

        // Flag injection: a leading dash would be parsed by tart's
        // swift-argument-parser as an option, not as a registry host.
        #expect(invalidHostReason("-evil") != nil)
        #expect(invalidHostReason("--help") != nil)
        // Whitespace and control characters are rejected too.
        #expect(invalidHostReason("gh cr.io") != nil)
        #expect(invalidHostReason("gh\u{07}cr.io") != nil)
        #expect(!RegistryCredentialRules.isValidHost("-evil"))
        #expect(!RegistryCredentialRules.isValidHost(""))
    }

    @Test func scrubberReplacesSecretAndItsBase64Encoding() {
        let secret = "tok-123"
        let text = "login failed for tok-123 (\(Data(secret.utf8).base64EncodedString()))"
        let scrubbed = RegistryCredentialScrubber.scrub(text, secret: secret)
        #expect(!scrubbed.contains(secret))
        #expect(scrubbed.contains(RegistryCredentialScrubber.replacement))
    }

    @Test func scrubberLeavesUnrelatedTextIntact() {
        let scrubbed = RegistryCredentialScrubber.scrub("registry unreachable", secret: "tok-1")
        #expect(scrubbed == "registry unreachable")
    }

    @Test func argumentErrorNormalizesWithoutFabricatedExitCode() {
        let payload = RegistryArgumentError.invalidHost(command: "login",
                                                        reason: "the host must not start with “-”")
            .normalized
        #expect(payload.operation == "login")
        #expect(payload.exitCode == nil)
        #expect(payload.message.contains("Invalid registry host"))

        let empty = RegistryArgumentError.emptyField(command: "login", field: "password").normalized
        #expect(empty.exitCode == nil)
        #expect(empty.message.contains("password"))
    }
}
