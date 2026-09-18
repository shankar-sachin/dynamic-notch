import AppKit
import SwiftUI

/// Countdown timers, shown live in the notch.
///
/// Nothing ticks on a schedule here. The end date is fixed when the timer
/// starts, one task sleeps until then, and the pill redraws itself from the
/// clock — so a long timer costs one sleeping task, not thousands of wakeups.
@MainActor
final class TimerService {
    private let model: NotchViewModel
    private var completion: Task<Void, Never>?
    /// Lets our presets match the duration Clock would have offered.
    weak var clock: ClockBridge?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start(_ duration: TimeInterval, label: String? = nil) {
        guard duration > 0 else { return }
        let state = TimerState(
            total: duration,
            endDate: .now.addingTimeInterval(duration),
            paused: nil,
            label: label
        )
        withAnimation(Motion.activity) { model.timer = state }
        model.select(.timer)
        schedule(for: duration)
        Log.app.info("timer started for \(duration, format: .fixed(precision: 0))s")
    }

    /// Whatever Clock is set to default to, so the two agree.
    var defaultDuration: TimeInterval { clock?.defaultDuration ?? 900 }

    func pause() {
        guard var timer = model.timer, !timer.isPaused else { return }
        timer.paused = timer.remaining()
        completion?.cancel()
        completion = nil
        withAnimation(Motion.pill) { model.timer = timer }
    }

    func resume() {
        guard var timer = model.timer, let left = timer.paused else { return }
        timer.paused = nil
        timer.endDate = .now.addingTimeInterval(left)
        withAnimation(Motion.pill) { model.timer = timer }
        schedule(for: left)
    }

    func add(_ seconds: TimeInterval) {
        guard var timer = model.timer else { return }
        timer.total += seconds
        if let left = timer.paused {
            timer.paused = left + seconds
        } else {
            timer.endDate = timer.endDate.addingTimeInterval(seconds)
        }
        withAnimation(Motion.pill) { model.timer = timer }
        if !timer.isPaused { schedule(for: timer.remaining()) }
    }

    func cancel() {
        completion?.cancel()
        completion = nil
        withAnimation(Motion.activity) { model.timer = nil }
    }

    func stop() {
        completion?.cancel()
        completion = nil
    }

    private func schedule(for duration: TimeInterval) {
        completion?.cancel()
        completion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func fire() {
        let label = model.timer?.label
        let total = model.timer?.total ?? 0
        withAnimation(Motion.activity) { model.timer = nil }

        NSSound(named: "Glass")?.play()
        model.present(.event(EventActivity(
            symbol: "timer",
            tint: .orange,
            title: label ?? "Timer done",
            detail: TimerState.clock(total) + " elapsed"
        )))
        // Worth looking up for: open so it's unmissable.
        model.expand()
        Log.app.info("timer finished")
    }
}
