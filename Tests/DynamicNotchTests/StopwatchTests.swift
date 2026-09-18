import Foundation
import Testing
@testable import DynamicNotch

@Suite("Stopwatch")
struct StopwatchTests {
    private let origin = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test("A running watch reads from the clock, so it can't drift")
    func runningElapsesFromTheClock() {
        let watch = StopwatchState(startedAt: origin, accumulated: 0)
        #expect(abs(watch.elapsed(at: origin.addingTimeInterval(12.5)) - 12.5) < 0.001)
    }

    @Test("A paused watch holds exactly what it had banked")
    func pausedHolds() {
        let watch = StopwatchState(startedAt: nil, accumulated: 42)
        #expect(watch.elapsed(at: origin.addingTimeInterval(999)) == 42)
        #expect(!watch.isRunning)
    }

    @Test("Time survives being paused and started again")
    func accumulationSurvivesPauses() {
        // 30s banked, running again for 5s.
        let watch = StopwatchState(startedAt: origin, accumulated: 30)
        #expect(abs(watch.elapsed(at: origin.addingTimeInterval(5)) - 35) < 0.001)
    }

    @Test("A lap's duration is its own, not the split")
    func lapDurationIsRelative() {
        let watch = StopwatchState(startedAt: nil, accumulated: 60, laps: [12, 27, 44])
        // Third lap ran from 27s to 44s.
        #expect(abs((watch.lastLapDuration ?? 0) - 17) < 0.001)
    }

    @Test("The first lap's duration is measured from zero")
    func firstLapMeasuresFromStart() {
        let watch = StopwatchState(startedAt: nil, accumulated: 20, laps: [12])
        #expect(abs((watch.lastLapDuration ?? 0) - 12) < 0.001)
    }

    @Test("With no laps there is no lap duration")
    func noLapsNoDuration() {
        #expect(StopwatchState().lastLapDuration == nil)
    }

    @Test("Precise formatting carries centiseconds", arguments: [
        (0.0, "0:00.00"), (9.42, "0:09.42"), (61.5, "1:01.50"), (3661.25, "1:01:01.25"),
    ])
    func preciseFormatting(seconds: TimeInterval, expected: String) {
        #expect(StopwatchState.precise(seconds) == expected)
    }

    @Test("A negative reading never renders as garbage")
    func negativeIsClamped() {
        #expect(StopwatchState.precise(-5) == "0:00.00")
        #expect(StopwatchState.coarse(-5) == "0:00")
    }

    @Test("The pill's reading drops the centiseconds")
    func coarseFormatting() {
        #expect(StopwatchState.coarse(61.9) == "1:02")
    }
}
