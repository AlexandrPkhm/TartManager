import Foundation

/// Parsed pull progress; nils mean "not known yet".
public struct PullProgress: Equatable, Sendable {
    public let fraction: Double?    // 0...1
    public let note: String?

    public init(fraction: Double?, note: String?) {
        self.fraction = fraction
        self.note = note
    }
}

/// Stateless parsing of tart's clone/pull output; re-parses the accumulated
/// buffer each time, so retry lines can never reset the bar.
public enum PullProgressParser {
    public static func latest(in text: String, retainedNote: String? = nil) -> PullProgress {
        // Last percentage wins; \r counts as a line separator.
        var fraction: Double?
        var cursor = text.startIndex
        while let match = text[cursor...].firstMatch(of: #/(\d+(?:\.\d+)?)%/#) {
            if let value = Double(match.1) {
                fraction = min(max(value / 100, 0), 1)
            }
            cursor = match.range.upperBound
        }
        return PullProgress(fraction: fraction, note: retainedNote ?? note(in: text))
    }

    /// The compressed-size / manifest note, with the unit tart printed
    /// preserved ("27.3 GB compressed", "500 MB compressed") (finding 6).
    static func note(in text: String) -> String? {
        if let size = text.firstMatch(of: #/pulling disk \((\d+(?:\.\d+)?) ([GM])B compressed\)/#) {
            return "\(size.1) \(size.2)B compressed"
        }
        if text.contains("pulling manifest") {
            return "pulling manifest…"
        }
        return nil
    }

    /// The last line tart printed about the failure (an "Error"-prefixed
    /// line) — the fatal message that supersedes mid-stream retry lines and
    /// progress banners (finding 2). `\r` counts as a separator.
    static func errorLine(in text: String) -> String? {
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        return lines.last(where: { $0.hasPrefix("Error") })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

/// Stateful progress tracking over the streamed clone output.
///
/// Owned by `TartClient.clone` (finding 8). Bounds its buffer (finding 13),
/// retains the once-seen size note and the last failure line across
/// trimming, and reports only actual changes (finding 12).
public final class PullProgressTracker: @unchecked Sendable {
    public static let maxBufferedCharacters = 65_536

    private let lock = NSLock()
    private var tail = ""
    private var _latest = PullProgress(fraction: nil, note: nil)
    private var _failureLine: String?

    public init() {}

    /// Appends a chunk; returns the new progress when it actually changed
    /// and nil otherwise — callers skip the UI hop on the nil path
    /// (finding 12).
    @discardableResult
    public func consume(_ chunk: String) -> PullProgress? {
        lock.lock()
        defer { lock.unlock() }
        tail += chunk
        if tail.count > Self.maxBufferedCharacters {
            tail = String(tail.suffix(Self.maxBufferedCharacters))
        }
        if let line = PullProgressParser.errorLine(in: tail) {
            _failureLine = line
        }
        // The note lives at the head of the session, which trimming drops:
        // it is captured once and carried forward instead (finding 13).
        let note = _latest.note ?? PullProgressParser.note(in: tail)
        let parsed = PullProgressParser.latest(in: tail, retainedNote: note)
        if parsed != _latest {
            _latest = parsed
            return parsed
        }
        return nil
    }

    public var latest: PullProgress {
        lock.lock()
        defer { lock.unlock() }
        return _latest
    }

    public var failureLine: String? {
        lock.lock()
        defer { lock.unlock() }
        return _failureLine
    }
}
