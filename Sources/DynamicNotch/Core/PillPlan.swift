import SwiftUI

/// Whether the mic or camera is live right now.
struct PrivacyState: Equatable, Sendable {
    var micInUse = false
    var cameraInUse = false

    var isActive: Bool { micInUse || cameraInUse }
    var symbol: String { cameraInUse ? "video.fill" : "mic.fill" }
    var tint: Color { cameraInUse ? .green : .orange }
    var title: String {
        switch (cameraInUse, micInUse) {
        case (true, true): "Camera & mic in use"
        case (true, false): "Camera in use"
        default: "Microphone in use"
        }
    }
}

/// One thing the closed pill can draw in one ear.
enum PillSlot: Equatable {
    case empty
    case artwork(NowPlayingSnapshot)
    case bars(NowPlayingSnapshot)
    case levelIcon(LevelActivity)
    case levelBar(LevelActivity)
    case eventIcon(EventActivity)
    case eventDetail(EventActivity)
    case timerGlyph(TimerState)
    case timerCountdown(TimerState)
    case stopwatchGlyph(StopwatchState)
    case stopwatchElapsed(StopwatchState)
    case dropIcon
    case dropLabel
    case privacy(PrivacyState)
    case locked
}

/// What the closed pill is showing, as two independent ears.
///
/// Two slots rather than one blob is the whole trick behind the iPhone's
/// island: a timer can run in the right ear while album art sits in the left,
/// and neither has to know the other exists.
struct PillPlan: Equatable {
    var leading: PillSlot = .empty
    var trailing: PillSlot = .empty
    /// Width, in multiples of `NotchLayout.accessoryWidth`.
    var units: Int = 0

    static let idle = PillPlan()
}

extension NotchViewModel {
    var pill: PillPlan {
        // Locked wins outright: nothing else should be on show at the lock
        // screen, and there's nothing you could act on anyway.
        if isLocked {
            return PillPlan(leading: .locked, trailing: .empty, units: 1)
        }

        // A live drag outranks everything: you're mid-gesture.
        if isDropTargeted {
            return PillPlan(leading: .dropIcon, trailing: .dropLabel, units: 5)
        }

        if let transient {
            switch transient {
            case .level(let level):
                return PillPlan(leading: .levelIcon(level), trailing: .levelBar(level), units: 4)
            case .event(let event):
                return PillPlan(leading: .eventIcon(event), trailing: .eventDetail(event), units: 5)
            }
        }

        // Dormant music keeps the panel but gives up the pill: a notch that
        // stays fat for a track you paused an hour ago is just clutter.
        let track = (nowPlaying?.isEmpty == false && !musicDormant) ? nowPlaying : nil
        // A countdown is going somewhere, so it outranks a stopwatch for the
        // one readout the pill has room for.
        let running = stopwatch?.isRunning == true ? stopwatch : nil

        switch (track, timer, running) {
        case (.some(let track), .some(let timer), _):
            // Both: art keeps the left ear, the countdown takes the right.
            return PillPlan(leading: .artwork(track), trailing: .timerCountdown(timer), units: 4)
        case (.some(let track), .none, .some(let watch)):
            return PillPlan(leading: .artwork(track), trailing: .stopwatchElapsed(watch), units: 4)
        case (.some(let track), .none, .none):
            return PillPlan(leading: .artwork(track), trailing: .bars(track), units: 2)
        case (.none, .some(let timer), _):
            return PillPlan(leading: .timerGlyph(timer), trailing: .timerCountdown(timer), units: 3)
        case (.none, .none, .some(let watch)):
            return PillPlan(leading: .stopwatchGlyph(watch), trailing: .stopwatchElapsed(watch), units: 3)
        case (.none, .none, .none):
            if privacy.isActive {
                return PillPlan(leading: .privacy(privacy), trailing: .empty, units: 1)
            }
            return .idle
        }
    }
}
