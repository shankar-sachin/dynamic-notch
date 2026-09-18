import Foundation

/// Where a countdown came from.
enum TimerSource: String, Equatable, Sendable {
    /// Started here, in the notch.
    case notch
    /// Running in Apple's Clock app; we're mirroring it.
    case clock

    var label: String {
        switch self {
        case .notch: "Timer"
        case .clock: "Clock"
        }
    }
}

/// A running (or paused) countdown.
///
/// Stored as an *end date* rather than a ticking number, so the UI can redraw
/// from the clock at whatever rate it likes and nothing drifts.
struct TimerState: Equatable, Sendable {
    var total: TimeInterval
    var endDate: Date
    /// Non-nil while paused: the time that was left when it stopped.
    var paused: TimeInterval?
    var label: String?
    var source: TimerSource = .notch

    var isPaused: Bool { paused != nil }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let paused { return paused }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        guard total > 0 else { return 0 }
        return min(max(0, 1 - remaining(at: date) / total), 1)
    }

    func isFinished(at date: Date = .now) -> Bool {
        !isPaused && remaining(at: date) <= 0
    }

    /// `4:59`, or `1:04:59` once it's over an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// The presets offered in the timer panel.
enum TimerPreset: TimeInterval, CaseIterable, Identifiable {
    case one = 60
    case three = 180
    case five = 300
    case ten = 600
    case twentyFive = 1500

    var id: TimeInterval { rawValue }
    var title: String {
        let minutes = Int(rawValue / 60)
        return "\(minutes)m"
    }
}
