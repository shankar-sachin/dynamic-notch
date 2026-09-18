import SwiftUI

/// Every curve in the app lives here.
///
/// A Dynamic Island only reads as *one object* if everything it does shares a
/// physical vocabulary. Views never spell out their own springs — they ask
/// `Motion` — so the whole surface accelerates and settles together.
enum Motion {
    /// Unfurling. Loose enough to overshoot a hair, which is what sells the rubber.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.72)

    /// Folding back up. Tighter than `open` — retreat should be calm, not springy.
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.86)

    /// The closed pill breathing: accessories appearing, width nudging out.
    static let pill = Animation.spring(response: 0.28, dampingFraction: 0.80)

    /// The instant micro-bump under the cursor before a real open commits.
    static let hint = Animation.spring(response: 0.22, dampingFraction: 0.70)

    /// Content crossfades *inside* a shape that is already the right size.
    static let content = Animation.spring(response: 0.32, dampingFraction: 0.90)

    /// Continuous values — a scrubber head, a level bar — that must never wobble.
    static let track = Animation.spring(response: 0.25, dampingFraction: 1.0)

    /// Transient toasts sliding through the pill.
    static let activity = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Picks the right shape animation for a transition between two modes.
    static func shape(from old: NotchMode, to new: NotchMode) -> Animation {
        if new == .expanded { return open }
        if old == .expanded { return close }
        return old == .hinted || new == .hinted ? hint : pill
    }
}

/// How long the pointer must linger before the notch commits to opening,
/// and how forgiving it is once you leave.
enum Dwell {
    static let open: Duration = .milliseconds(120)
    static let close: Duration = .milliseconds(350)
    /// Dragging a file gets a snappier open — you are already committed.
    static let drag: Duration = .milliseconds(40)
}
