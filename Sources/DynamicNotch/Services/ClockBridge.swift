import AppKit
import SwiftUI

/// Mirrors Apple's Clock timers into the notch.
///
/// Clock has no scripting dictionary, no URL scheme and no public API — but its
/// daemon, `mobiletimerd`, keeps timer state in its own preferences domain, and
/// that we can read. Start a timer in Clock (or ask Siri to) and it shows up
/// here alongside everything else.
///
/// This is a read-only mirror, deliberately. Writing into another daemon's
/// preferences to try to *control* Clock would be fighting the process that
/// owns that state, and would break the first time Apple changes the schema.
/// Where the schema is concerned this code assumes as little as possible: it
/// goes looking for a date, rather than trusting any particular key layout.
@MainActor
final class ClockBridge {
    private let model: NotchViewModel
    private var task: Task<Void, Never>?
    private var lastSeen: Date?
    #if DEBUG
    /// Flipped on by `notchctl clockdiag` while working out the schema.
    var diagnose = false
    #endif

    private let domain = "com.apple.mobiletimerd"

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sync()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Clock's own default, so a timer started here matches the one you'd get there.
    var defaultDuration: TimeInterval {
        let value = CFPreferencesCopyAppValue(
            "MTTimerDefaultDuration" as CFString,
            domain as CFString
        ) as? Double
        return value ?? 900
    }

    // MARK: Syncing

    private func sync() {
        let clockTimer = readClockTimer()
        #if DEBUG
        if diagnose {
            Log.app.error("clock sync: read=\(clockTimer.map { "timer \($0.remaining())s left" } ?? "nil", privacy: .public) model=\(self.model.timer.map { "\($0.source.rawValue)" } ?? "nil", privacy: .public)")
        }
        #endif

        // A timer started here always wins: it's the one you asked us for.
        if let existing = model.timer, existing.source == .notch { return }

        switch (clockTimer, model.timer) {
        case (.some(let fresh), .none):
            withAnimation(Motion.activity) { model.timer = fresh }
            Log.app.info("mirroring Clock timer, \(fresh.remaining(), format: .fixed(precision: 0))s left")

        case (.some(let fresh), .some(let current)):
            // Only re-animate when it's genuinely a different timer; otherwise
            // let the view keep counting down from the end date it already has.
            if abs(fresh.endDate.timeIntervalSince(current.endDate)) > 1.5
                || fresh.isPaused != current.isPaused
            {
                model.timer = fresh
            }

        case (.none, .some(let current)) where current.source == .clock:
            withAnimation(Motion.activity) { model.timer = nil }
            Log.app.info("Clock timer ended")

        default:
            break
        }
    }

    // MARK: Reading mobiletimerd

    private func readClockTimer() -> TimerState? {
        // Ask cfprefsd rather than reading the file: the daemon may be holding
        // recent writes in memory, and the file on disk can lag behind.
        CFPreferencesAppSynchronize(domain as CFString)
        guard let root = CFPreferencesCopyAppValue("MTTimers" as CFString, domain as CFString)
            as? [String: Any],
            let entries = root["MTTimers"] as? [[String: Any]]
        else { return nil }

        for entry in entries {
            // Each record is wrapped in a single "$MTTimer" key.
            guard let timer = (entry["$MTTimer"] as? [String: Any]) ?? entry.values.first as? [String: Any]
            else { continue }
            if let state = Self.state(from: timer) { return state }
        }
        return nil
    }

    /// Turns one of `mobiletimerd`'s records into a timer, or nothing.
    ///
    /// The shapes, as observed on macOS 27:
    ///
    ///     running:  MTTimerFireTimerClass = MTTimerDate
    ///               MTTimerFireTime = { "$MTTimerDate" = { MTTimerTimeDate = <date> } }
    ///               MTTimerState = 3
    ///
    ///     dormant:  MTTimerFireTimerClass = MTTimerTimeInterval
    ///               MTTimerFireTime = { "$MTTimerTimeInterval" = { MTTimerTimeInterval = 900 } }
    ///               MTTimerState = 1
    ///
    /// Clock always keeps one dormant record around holding the duration the UI
    /// is set to — it is not a running timer and must not be shown as one.
    /// `static` so the schema can be tested without a running app.
    nonisolated static func state(from timer: [String: Any]) -> TimerState? {
        let duration = (timer["MTTimerDuration"] as? Double) ?? 0
        guard duration > 0 else { return nil }

        let title = timer["MTTimerTitle"] as? String
        // Clock names the unnamed one CURRENT_TIMER; that's plumbing, not a label.
        let label = (title == "CURRENT_TIMER" || title?.isEmpty == true) ? nil : title

        guard let fireTime = timer["MTTimerFireTime"] as? [String: Any] else { return nil }

        // A running timer carries an absolute fire date somewhere inside; a
        // dormant one only carries the interval it *would* run for. Rather than
        // hard-coding the wrapper key, go looking for the date.
        if let fireDate = firstDate(in: fireTime) {
            guard fireDate.timeIntervalSinceNow > 0.5 else { return nil }
            return TimerState(
                total: duration,
                endDate: fireDate,
                paused: nil,
                label: label,
                source: .clock
            )
        }

        // Paused: Clock is holding a remaining interval that isn't the full
        // duration, which a dormant timer never does.
        if let remaining = firstDouble(in: fireTime),
           remaining > 0.5, remaining < duration - 0.5
        {
            return TimerState(
                total: duration,
                endDate: .now.addingTimeInterval(remaining),
                paused: remaining,
                label: label,
                source: .clock
            )
        }

        return nil
    }

    /// Depth-first search for a date anywhere in a nested plist fragment.
    nonisolated static func firstDate(in value: Any, depth: Int = 0) -> Date? {
        guard depth < 5 else { return nil }
        if let date = value as? Date { return date }
        if let dictionary = value as? [String: Any] {
            for nested in dictionary.values {
                if let found = firstDate(in: nested, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    nonisolated static func firstDouble(in value: Any, depth: Int = 0) -> Double? {
        guard depth < 5 else { return nil }
        if let number = value as? Double { return number }
        if let dictionary = value as? [String: Any] {
            for nested in dictionary.values {
                if let found = firstDouble(in: nested, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// Hand the user over to Clock itself, which owns the timer we're mirroring.
    func openClock() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
