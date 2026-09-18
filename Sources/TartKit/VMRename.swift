import Foundation
import os

/// Rename orchestration as a hermetic TartKit unit (injected operations).
/// Fresh-list pre-validation happens before any spawn: a vanished source is
/// a race-tolerant no-op; a running/suspended source or an occupied target is
/// refused; tart failures propagate for the standard sheet (a VM renamed
/// externally between sheet-open and submit surfaces tart's rejection here).
public enum VMRename: Sendable {
    public enum Outcome: Equatable, Sendable {
        case renamed
        case sourceVanished
    }

    public struct Ops: Sendable {
        public var list: @Sendable () throws -> [VMEntry]
        public var rename: @Sendable (String, String) throws -> Void

        public init(list: @escaping @Sendable () throws -> [VMEntry],
                    rename: @escaping @Sendable (String, String) throws -> Void) {
            self.list = list
            self.rename = rename
        }
    }

    private static let log = Logger.rename

    public static func perform(from: String, to: String, ops: Ops) throws -> Outcome {
        let entries = try ops.list()
        guard let source = entries.first(where: { $0.name == from }) else {
            Self.log.notice("rename: \(from, privacy: .public) no longer listed — clean no-op")
            return .sourceVanished
        }
        guard source.isStoppedLocal else {
            Self.log.error("rename pre-flight: \(from, privacy: .public) is \(source.state, privacy: .public) — refusing before spawn")
            throw TartClientError.commandFailed(
                command: "rename", exitCode: -1, stdout: "",
                stderr: "Rename refused — " + from + " is not stopped. Stop the VM first.")
        }
        guard !entries.contains(where: { $0.name == to }) else {
            Self.log.error("rename pre-flight: \(to, privacy: .public) already exists — refusing before spawn")
            throw TartClientError.commandFailed(
                command: "rename", exitCode: -1, stdout: "",
                stderr: "A VM named " + to + " already exists.")
        }
        Self.log.notice("rename: starting \(from, privacy: .public) → \(to, privacy: .public)")
        do {
            try ops.rename(from, to)
        } catch {
            Self.log.error("rename: \(from, privacy: .public) → \(to, privacy: .public) failed — \(String(describing: error), privacy: .public)")
            throw error
        }
        Self.log.notice("rename: completed — \(from, privacy: .public) → \(to, privacy: .public)")
        return .renamed
    }
}
