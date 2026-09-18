import AppKit
import SwiftUI

/// The stopwatch, run entirely in the notch.
///
/// There's no ticking task: the state holds a start date, and the views derive
/// the reading from the clock whenever they redraw. Running for an hour costs
/// exactly nothing while the notch is closed and nobody is looking at it.
@MainActor
final class StopwatchService {
    private let model: NotchViewModel

    init(model: NotchViewModel) {
        self.model = model
    }

    func toggle() {
        if model.stopwatch?.isRunning == true {
            pause()
        } else {
            start()
        }
    }

    func start() {
        var state = model.stopwatch ?? StopwatchState()
        guard !state.isRunning else { return }
        state.startedAt = .now
        withAnimation(Motion.activity) { model.stopwatch = state }
        model.select(.timer)
    }

    func pause() {
        guard var state = model.stopwatch, let startedAt = state.startedAt else { return }
        state.accumulated += Date.now.timeIntervalSince(startedAt)
        state.startedAt = nil
        withAnimation(Motion.pill) { model.stopwatch = state }
    }

    func lap() {
        guard var state = model.stopwatch, state.isRunning else { return }
        state.laps.append(state.elapsed())
        withAnimation(Motion.content) { model.stopwatch = state }
    }

    func reset() {
        withAnimation(Motion.activity) { model.stopwatch = nil }
    }
}
