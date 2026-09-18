import Foundation
import os

/// The delete job body as a hermetic TartKit unit (injected operations), so
/// the issue's automated-verification requirements — running/suspended
/// refusal before spawn and race reconciliation — are testable without a real
/// tart or an app instance. Run by `AppModel.startDelete` inside a JobManager
/// job; `ops.delete` is wired to `TartClient.delete(name:timeout:)`, the
/// single, argv-tested delete primitive (no command construction lives in the
/// app layer). Nonisolated and `Sendable`, so the detached job body never
/// touches a main-actor-isolated member.
public struct VMDeleteJob: Sendable {
    /// Watchdog bound for the blocking `tart delete` inside the UNCANCELLABLE
    /// job (finding 3): long enough for tens-of-GB removals on slow external
    /// SSDs, short enough that a wedged tart cannot leave a permanently
    /// running job. The client's ProcessRunner deadline (SIGTERM → SIGKILL,
    /// the Issue 11 mechanism) terminates the process on expiry and
    /// `TartClient.delete` throws `.timedOut`, which this job surfaces. The
    /// client's 10 s default stays reserved for Issue 11's cleanup path.
    public static let deleteTimeout: TimeInterval = 600

    public struct Ops: Sendable {
        public var list: @Sendable () throws -> [VMEntry]
        public var delete: @Sendable (String, TimeInterval) throws -> Void

        public init(list: @escaping @Sendable () throws -> [VMEntry],
                    delete: @escaping @Sendable (String, TimeInterval) throws -> Void) {
            self.list = list
            self.delete = delete
        }
    }

    public let name: String
    public let ops: Ops

    private static let log = Logger.deleteVM

    public init(name: String, ops: Ops) {
        self.name = name
        self.ops = ops
    }

    /// Runs the deletion. No cancellation check exists by design: the
    /// `deleteVM` kind is uncancellable (`JobManager.cancel` is a no-op), so
    /// `context.isCancelled` could never be true here — the policy is pinned
    /// by `cancelIsIgnoredForDeleteJobs` instead of dead code.
    public func run(context: JobContext) throws {
        // Pre-flight on a FRESH list (not the cached poll): a VM already
        // gone is a logged clean no-op; a VM that became running/suspended
        // since the UI gate is refused before any spawn.
        let entries = try ops.list()
        if let entry = entries.first(where: { $0.name == name }) {
            guard entry.isStoppedLocal else {
                Self.log.error("delete pre-flight: \(name, privacy: .public) is \(entry.state, privacy: .public) — refusing before spawn")
                throw TartClientError.commandFailed(
                    command: "delete", exitCode: -1, stdout: "",
                    stderr: "Delete refused — " + name + " is not stopped. Stop the VM first.")
            }
        } else {
            Self.log.notice("delete: \(name, privacy: .public) already absent at launch — clean no-op")
            return
        }

        context.report(PullProgress(fraction: nil, note: "deleting…"))
        Self.log.notice("delete: starting \(name, privacy: .public)")
        let began = Date()
        do {
            try ops.delete(name, Self.deleteTimeout)
        } catch {
            let failure = (error as? TartClientError)
                ?? TartClientError.commandFailed(command: "delete", exitCode: -1,
                                                 stdout: "", stderr: String(describing: error))
            let duration = Date().timeIntervalSince(began)
            // Race tolerance: deleted externally while we were in flight.
            // A failed re-list degrades conservatively to "still present"
            // (rethrow) — never a wrongful silent success.
            let stillPresent = (try? ops.list())?.contains { $0.name == name } ?? true
            if !stillPresent {
                Self.log.notice("delete: \(name, privacy: .public) disappeared mid-action after \(String(format: "%.1f", duration), privacy: .public)s — clean no-op")
                return
            }
            Self.log.error("delete: failed after \(String(format: "%.1f", duration), privacy: .public)s — \(String(describing: failure), privacy: .public)")
            throw failure
        }
        Self.log.notice("delete: completed — \(name, privacy: .public) removed in \(String(format: "%.1f", Date().timeIntervalSince(began)), privacy: .public)s")
    }
}
