import Testing
import Foundation
@testable import TartKit

@Suite @MainActor struct StorageRecheckTimerTests {
    @Test func defaultIntervalIsThirtySeconds() {
        #expect(StorageRecheckTimer.defaultInterval == 30)
    }

    @Test func ticksRepeatedlyUntilStopped() async throws {
        let timer = StorageRecheckTimer(interval: 0.02)
        var ticks = 0
        timer.start { ticks += 1 }
        #expect(timer.isRunning)
        try await Task.sleep(for: .milliseconds(200))
        timer.stop()
        #expect(!timer.isRunning)
        #expect(ticks >= 2)
        let stoppedAt = ticks
        try await Task.sleep(for: .milliseconds(100))
        #expect(ticks == stoppedAt)
    }

    @Test func secondStartKeepsTheFirstSchedule() async throws {
        let timer = StorageRecheckTimer(interval: 0.05)
        var first = 0
        var second = 0
        timer.start { first += 1 }
        timer.start { second += 1 }
        try await Task.sleep(for: .milliseconds(200))
        timer.stop()
        #expect(first >= 1)
        #expect(second == 0)
    }

    @Test func doesNotTickBeforeTheFirstInterval() async throws {
        let timer = StorageRecheckTimer(interval: 10)
        var ticks = 0
        timer.start { ticks += 1 }
        try await Task.sleep(for: .milliseconds(50))
        timer.stop()
        #expect(ticks == 0)
    }
}
