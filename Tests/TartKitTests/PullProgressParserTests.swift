import Testing
import Foundation
@testable import TartKit

@Suite struct PullProgressParserTests {
    /// Verbatim format captured from the real 27.3 GB GHCR pull on this host.
    static let realSession = """
    pulling manifest...
    pulling disk (27.3 GB compressed)...
    14%
    Error pulling disk layer 12: "The network connection was lost.", attempting to re-try...
    19%
    """

    @Test func parsesLatestPercentFromRealSession() {
        let progress = PullProgressParser.latest(in: Self.realSession)
        #expect(progress.fraction == 0.19)
        #expect(progress.note == "27.3 GB compressed")
    }

    @Test func retryLinesNeverResetProgress() {
        let afterRetry = "pulling disk (27.3 GB compressed)...\n14%\n" +
            "Error pulling disk layer 12: \"The network connection was lost.\", " +
            "attempting to re-try...\n"
        let progress = PullProgressParser.latest(in: afterRetry)
        #expect(progress.fraction == 0.14)
    }

    @Test func carriageReturnsActAsSeparators() {
        let progress = PullProgressParser.latest(in: "14%\r19%\r31%")
        #expect(progress.fraction == 0.31)
    }

    @Test func manifestPhaseHasNoFractionButANote() {
        let progress = PullProgressParser.latest(in: "pulling manifest...")
        #expect(progress.fraction == nil)
        #expect(progress.note == "pulling manifest…")
    }

    @Test func fractionalPercentsClampIntoRange() {
        let progress = PullProgressParser.latest(in: "100%\n199%")
        #expect(progress.fraction == 1.0)
    }

    @Test func megabyteNoteKeepsItsUnit() {
        // finding 6: the unit tart printed is preserved, not re-rendered as GB.
        let progress = PullProgressParser.latest(in: "pulling disk (500 MB compressed)...\n10%")
        #expect(progress.note == "500 MB compressed")
    }

    @Test func garbageYieldsNothing() {
        let progress = PullProgressParser.latest(in: "nothing to see")
        #expect(progress.fraction == nil)
        #expect(progress.note == nil)
    }

    @Test func failureLineExtractsLastErrorMessage() {
        // finding 2: the LAST "Error"-prefixed line is tart's fatal message;
        // earlier retry lines are superseded.
        let output = "14%\n" +
            "Error pulling disk layer 12: \"The network connection was lost.\", attempting to re-try...\n" +
            "19%\nError: manifest unknown: nope\n"
        #expect(PullProgressParser.errorLine(in: output) == "Error: manifest unknown: nope")
        #expect(PullProgressParser.errorLine(in: "14%\r19%") == nil)
    }

    @Test func trackerReportsOnlyChangedProgress() {
        // finding 12: unchanged parses yield nil so callers skip UI churn.
        let tracker = PullProgressTracker()
        let first = tracker.consume("10%")
        let duplicate = tracker.consume("10%")
        let advanced = tracker.consume("20%")
        #expect(first?.fraction == 0.1)
        #expect(duplicate == nil)
        #expect(advanced?.fraction == 0.2)
    }

    @Test func trackerCapsItsBufferAndStillParsesTail() {
        // finding 13: a long session costs O(cap) per chunk, never O(n²).
        let tracker = PullProgressTracker()
        tracker.consume(String(repeating: "x", count: 200_000))
        let parsed = tracker.consume("42%")
        #expect(parsed?.fraction == 0.42)
    }

    @Test func trackerRetainsNoteAfterBufferTrim() {
        let tracker = PullProgressTracker()
        tracker.consume("pulling disk (27.3 GB compressed)...\n")
        tracker.consume(String(repeating: "x", count: 200_000))
        let parsed = tracker.consume("50%")
        #expect(parsed?.fraction == 0.5)
        #expect(parsed?.note == "27.3 GB compressed")
    }

    @Test func trackerRecordsFailureLine() {
        let tracker = PullProgressTracker()
        tracker.consume("14%\nError: boom\n")
        tracker.consume("19%")
        #expect(tracker.failureLine == "Error: boom")
    }

    @Test func accumulatorAppendsAndReadsThreadSafely() {
        let accumulator = TextAccumulator()
        let group = DispatchGroup()
        for i in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                accumulator.append("chunk\(i)-")
                group.leave()
            }
        }
        group.wait()
        #expect(accumulator.value.count == 8 * ("chunkX-".count))
        #expect(accumulator.value.hasPrefix("chunk"))
        #expect(accumulator.value.hasSuffix("-"))
    }

    @Test func accumulatorCapsItsBufferKeepingTheTail() {
        // finding 13: bounded by design — a pull of any length costs a fixed
        // maximum of retained text.
        let accumulator = TextAccumulator()
        accumulator.append(String(repeating: "x", count: 100_000))
        #expect(accumulator.value.count == TextAccumulator.maxBufferedCharacters)
        accumulator.append("tail")
        #expect(accumulator.value.hasSuffix("tail"))
    }
}
