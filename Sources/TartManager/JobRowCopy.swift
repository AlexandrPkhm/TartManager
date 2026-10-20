import Foundation
import TartKit

/// The text for one `JobRowView` row. Kept apart from the view so each job
/// kind and phase maps to tested copy.
struct JobRowCopy: Equatable {
    /// One-line title that names the operation and its VM.
    let title: String
    /// One-line caption below the title: progress while running, the error
    /// message after a failure.
    let caption: String

    static let sectionTitle = "JOBS"
    static let cancelLabel = "Cancel"
    static let dismissLabel = "Dismiss"
    static let detailsLabel = "Details"

    init(job: JobInfo, now: Date) {
        title = Self.title(for: job.kind)
        switch job.phase {
        case .running:
            var parts: [String] = []
            if let fraction = job.progress?.fraction {
                parts.append("\(Int(fraction * 100))%")
            }
            if let note = job.progress?.note, !note.isEmpty {
                parts.append(note)
            }
            parts.append(Self.elapsed(from: job.createdAt, to: now))
            caption = parts.joined(separator: " · ")
        case .failed:
            caption = job.error?.message ?? "Failed"
        case .completed:
            caption = job.summary ?? "Done"
        case .cancelled:
            caption = "Cancelled"
        }
    }

    static func title(for kind: JobInfo.Kind) -> String {
        switch kind {
        case .clone(let name, let source):
            return "Creating “\(name)” from \(shortSource(source))"
        case .importArchive(let name, let path):
            return "Importing “\(name)” from \((path as NSString).lastPathComponent)"
        case .exportSnapshot(let name):
            return "Snapshotting “\(name)”"
        case .restoreSnapshot(let name):
            return "Restoring “\(name)” from a snapshot"
        case .createFromIPSW(let name):
            return "Installing “\(name)” from an IPSW"
        case .deleteVM(let name):
            return "Deleting “\(name)”"
        case .replaceDisk(let name, _):
            return "Replacing the disk of “\(name)”"
        case .prune:
            return "Pruning caches"
        }
    }

    /// Elapsed time as `m:ss`, or `h:mm:ss` from one hour on. A clock skew
    /// that puts `now` before `start` shows `0:00`.
    static func elapsed(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private static func shortSource(_ source: String) -> String {
        source.hasPrefix("ghcr.io/cirruslabs/")
            ? String(source.dropFirst("ghcr.io/cirruslabs/".count))
            : source
    }
}
