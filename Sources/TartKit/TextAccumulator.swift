import Foundation

/// Thread-safe accumulation of streamed text chunks, bounded by design
/// (finding 13): the buffer keeps at most `maxBufferedCharacters` characters
/// (its tail), so a pull of any length has a fixed memory ceiling.
public final class TextAccumulator: @unchecked Sendable {
    /// Same budget as Issue 6's analyzer capture cap: 64 KiB per stream.
    public static let maxBufferedCharacters = 65_536

    private let lock = NSLock()
    private var text = ""

    public init() {}

    public func append(_ chunk: String) {
        lock.lock()
        text += chunk
        if text.count > Self.maxBufferedCharacters {
            text = String(text.suffix(Self.maxBufferedCharacters))
        }
        lock.unlock()
    }

    public var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
