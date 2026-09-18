import Foundation

/// A stopwatch, stored as "time banked so far" plus "when the current run
/// started" — so the display can be derived from the clock at any frame rate
/// and nothing drifts, however long it runs.
struct StopwatchState: Equatable, Sendable {
    /// When the current run began; `nil` while paused.
    var startedAt: Date?
    /// Time banked from previous runs.
    var accumulated: TimeInterval = 0
    /// Elapsed time at each lap, in the order they were taken.
    var laps: [TimeInterval] = []

    var isRunning: Bool { startedAt != nil }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// The most recent lap's own duration, not its split.
    var lastLapDuration: TimeInterval? {
        guard let last = laps.last else { return nil }
        let previous = laps.count >= 2 ? laps[laps.count - 2] : 0
        return last - previous
    }

    /// `1:04.28` — centiseconds, the way a stopwatch should read.
    ///
    /// Everything is converted to whole centiseconds up front. Splitting the
    /// fraction off a `Double` and scaling it is what you reach for first, and
    /// it's wrong: 9.42 leaves a fraction of 0.41999…, which truncates to 41.
    static func precise(_ seconds: TimeInterval) -> String {
        let centisTotal = Int((max(0, seconds) * 100).rounded())
        let hours = centisTotal / 360_000
        let minutes = (centisTotal % 360_000) / 6_000
        let secs = (centisTotal % 6_000) / 100
        let centis = centisTotal % 100
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, secs, centis)
        }
        return String(format: "%d:%02d.%02d", minutes, secs, centis)
    }

    /// `1:04` — for the pill, where centiseconds would just be noise.
    static func coarse(_ seconds: TimeInterval) -> String {
        TimerState.clock(max(0, seconds))
    }
}
