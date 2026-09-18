import SwiftUI

/// Timer and stopwatch, both driven entirely from here.
///
/// Apple's Clock can't be controlled by another app — no scripting dictionary,
/// no URL scheme, and its timers belong to a daemon that won't take instructions
/// from us. So rather than leaving you to bounce over to Clock, everything here
/// is ours and fully operable: start, pause, extend, lap, reset. A timer running
/// in Clock is still mirrored, clearly marked as theirs, since that's the one
/// case where all we can honestly do is show it.
struct TimePanel: View {
    let model: NotchViewModel
    let timers: TimerService
    let stopwatch: StopwatchService
    var clock: ClockBridge?

    @State private var mode: Mode = .timer

    enum Mode: String, CaseIterable, Identifiable {
        case timer, stopwatch
        var id: String { rawValue }
        var title: String { self == .timer ? "Timer" : "Stopwatch" }
        var symbol: String { self == .timer ? "timer" : "stopwatch" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                switch mode {
                case .timer: TimerFace(model: model, service: timers)
                case .stopwatch: StopwatchFace(model: model, service: stopwatch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switcher
        }
        .onAppear {
            // Land on whatever is actually running.
            if model.timer != nil { mode = .timer }
            else if model.stopwatch != nil { mode = .stopwatch }
        }
    }

    private var switcher: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 5) {
                ForEach(Mode.allCases) { option in
                    let selected = mode == option
                    Button {
                        withAnimation(Motion.content) { mode = option }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 12, weight: .semibold))
                            Text(option.title)
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.45))
                        .frame(width: 62, height: 38)
                        .glassEffect(selected ? Glass.control : .identity, in: .rect(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    // Running things announce themselves even when not selected.
                    .overlay(alignment: .topTrailing) {
                        if isLive(option), !selected {
                            Circle()
                                .fill(option == .timer ? .orange : .cyan)
                                .frame(width: 5, height: 5)
                                .offset(x: -5, y: 5)
                        }
                    }
                }
            }
        }
    }

    private func isLive(_ option: Mode) -> Bool {
        switch option {
        case .timer: model.timer != nil
        case .stopwatch: model.stopwatch?.isRunning == true
        }
    }
}

// MARK: - Timer

private struct TimerFace: View {
    let model: NotchViewModel
    let service: TimerService

    var body: some View {
        if let timer = model.timer {
            running(timer)
        } else {
            presets
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Start a timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(TimerPreset.allCases) { preset in
                        Button {
                            service.start(preset.rawValue)
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 32)
                                .glassEffect(Glass.control, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("It keeps counting in the notch while you work.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
        }
    }

    private func running(_ timer: TimerState) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = timer.remaining(at: context.date)

            HStack(spacing: 15) {
                CountdownRing(
                    progress: timer.progress(at: context.date),
                    isPaused: timer.isPaused
                )
                .frame(width: 78, height: 78)
                .overlay {
                    Text(TimerState.clock(remaining))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        if timer.source == .clock {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        Text(status(timer))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if timer.source == .clock {
                        // Clock's daemon owns this one; we can show it, not steer it.
                        Text("Started in Clock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        controls(timer)
                    }
                }
            }
        }
    }

    private func controls(_ timer: TimerState) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 6) {
                NotchButton(size: 32, filled: true, tint: .orange) {
                    timer.isPaused ? service.resume() : service.pause()
                } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }

                Button {
                    service.add(60)
                } label: {
                    Text("+1m")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 32)
                        .glassEffect(Glass.control, in: .capsule)
                }
                .buttonStyle(.plain)

                NotchButton(size: 32) {
                    service.cancel()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
            }
        }
    }

    private func status(_ timer: TimerState) -> String {
        if timer.source == .clock {
            return timer.label ?? (timer.isPaused ? "Paused in Clock" : "Running in Clock")
        }
        return timer.isPaused ? "Paused" : "Counting down"
    }
}

// MARK: - Stopwatch

private struct StopwatchFace: View {
    let model: NotchViewModel
    let service: StopwatchService

    var body: some View {
        let watch = model.stopwatch ?? StopwatchState()

        HStack(spacing: 15) {
            // 20Hz only while it's actually running.
            TimelineView(.periodic(from: .now, by: watch.isRunning ? 0.03 : 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(StopwatchState.precise(watch.elapsed(at: context.date)))
                        .font(.system(size: 30, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    if let lap = watch.lastLapDuration {
                        Text("Lap \(watch.laps.count) · \(StopwatchState.precise(lap))")
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        Text(watch.isRunning ? "Running" : (watch.elapsed() > 0 ? "Paused" : "Ready"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 6) {
                    NotchButton(size: 34, filled: true, tint: .cyan) {
                        service.toggle()
                    } label: {
                        Image(systemName: watch.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                    }

                    Button {
                        watch.isRunning ? service.lap() : service.reset()
                    } label: {
                        Text(watch.isRunning ? "Lap" : "Reset")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(watch.elapsed() > 0 || watch.isRunning ? 1 : 0.35))
                            .frame(width: 48, height: 32)
                            .glassEffect(Glass.control, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!watch.isRunning && watch.elapsed() == 0)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// The draining ring, shared by the panel and reused for its glow.
struct CountdownRing: View {
    var progress: Double
    var isPaused: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.13), lineWidth: 6)
            Circle()
                .trim(from: 0, to: 1 - progress)
                .stroke(
                    isPaused
                        ? AnyShapeStyle(.white.opacity(0.45))
                        : AnyShapeStyle(AngularGradient(colors: [.orange, .yellow, .orange], center: .center)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .orange.opacity(isPaused ? 0 : 0.5), radius: 8)
        }
    }
}
