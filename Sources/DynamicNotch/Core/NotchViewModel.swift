import AppKit
import SwiftUI

/// The single source of truth for what the notch is doing.
///
/// Views read `mode` / `presentation`; services push content in. Every state
/// change is wrapped in the curve that belongs to it, so animation intent lives
/// next to the state change rather than scattered across the view tree.
@MainActor
@Observable
final class NotchViewModel {
    // MARK: Geometry

    var metrics: NotchMetrics
    let settings: NotchSettings

    // MARK: Content

    var nowPlaying: NowPlayingSnapshot?
    /// The user turned down the Automation prompt; the player panel offers a fix.
    var mediaAccessDenied = false
    private(set) var transient: TransientActivity?
    var shelf: [ShelfItem] = []
    var timer: TimerState?
    var stopwatch: StopwatchState?
    var bluetooth: [BluetoothDevice] = []
    /// A device worth interrupting for — shown full-panel, iPhone style.
    var deviceSpotlight: BluetoothDevice?
    var privacy = PrivacyState()
    /// The screen is locked (or this session was switched away from).
    var isLocked = false
    /// Paused long enough that the pill has handed the notch back. The track is
    /// still here — open the panel and it's waiting — it just isn't on show.
    var musicDormant = false
    /// Left edge of the menu bar's status items, in global coordinates, as far
    /// as we can see it. The closed pill won't spread past it.
    var menuBarLeftEdge: CGFloat?
    var selectedTab: NotchTab = .home
    /// A drag is hovering over us — hold open and show the catch target.
    var isDropTargeted = false

    // MARK: Interaction

    private(set) var isExpanded = false
    private(set) var isHinting = false
    /// Set while something must not be interrupted: a drag, a scrub, a menu.
    var isInteractionLocked = false
    /// A menu is open somewhere; stay out of its way.
    var isMenuBarBusy = false
    /// The pointer is over the notch. Kept by the window controller, which is
    /// the thing actually watching the mouse — reading `NSEvent.mouseLocation`
    /// from in here made behaviour depend on global state nothing could control.
    var isPointerInside = false

    /// Wired up by the media service; the UI never talks to Music or Spotify itself.
    var onMediaCommand: ((MediaCommand) -> Void)?
    /// Opens the Automation pane and re-asks, when the user was denied.
    var onRequestMediaAccess: (() -> Void)?
    /// The shelf's backing store, for the shelf panel's own actions.
    weak var shelfStore: ShelfStore?
    /// The view a share sheet should hang off.
    var shareAnchor: (() -> NSView?)?

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var transientTask: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?

    init(metrics: NotchMetrics, settings: NotchSettings = .shared) {
        self.metrics = metrics
        self.settings = settings
    }

    // MARK: Derived state

    /// Width units of ambient content, in multiples of `NotchLayout.accessoryWidth`.
    var accessoryUnits: Int { pill.units }

    var mode: NotchMode {
        if isExpanded { return .expanded }
        if isHinting { return .hinted }
        if accessoryUnits > 0 { return .ambient }
        return .idle
    }

    var presentation: NotchPresentation {
        NotchPresentation.resolve(
            mode: mode,
            notch: metrics.notchSize,
            accessories: accessoryUnits,
            maxSpread: maxSpread
        )
    }

    /// How far the closed pill may grow on each side before it starts covering
    /// menu bar icons. `nil` when we have nothing to go on.
    ///
    /// The panel deliberately ignores this: you opened it, and it's a transient
    /// overlay. The *closed* pill is different — it sits there for the length of
    /// a song, and a pill that quietly eats your battery icon is a bug.
    private var maxSpread: CGFloat? {
        guard let edge = menuBarLeftEdge else { return nil }
        let notchRightEdge = metrics.notchCenterX + metrics.notchSize.width / 2
        let room = edge - notchRightEdge - 8
        // Below a certain point there's no sensible pill left; take the room we
        // have rather than collapsing to nothing.
        return max(26, room)
    }

    /// Global rect the visible body occupies, hanging from the top of the screen.
    var bodyRect: CGRect {
        let p = presentation
        return CGRect(
            x: metrics.notchCenterX - p.outerWidth / 2,
            y: metrics.screenFrame.maxY - p.bodySize.height,
            width: p.outerWidth,
            height: p.bodySize.height
        )
    }

    /// Where the pointer counts as "on the notch". Generous once we're open so a
    /// wobble near the edge doesn't slam it shut mid-click.
    var hoverRect: CGRect {
        let slop: CGFloat = isExpanded ? 14 : 5
        return bodyRect.insetBy(dx: -slop, dy: -slop)
    }

    // MARK: Pointer

    func pointerEntered(dragging: Bool = false) {
        closeTask?.cancel()
        closeTask = nil
        guard !isExpanded, !isMenuBarBusy, !isLocked else { return }
        // A drag is an explicit gesture, so it opens even with hover turned off.
        guard dragging || settings.hoverToOpen else { return }

        if !isHinting {
            withAnimation(Motion.hint) { isHinting = true }
        }
        guard openTask == nil else { return }

        openTask = Task { [weak self] in
            try? await Task.sleep(for: dragging ? Dwell.drag : Dwell.open)
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    func pointerExited() {
        openTask?.cancel()
        openTask = nil

        if isHinting {
            withAnimation(Motion.close) { isHinting = false }
        }
        guard isExpanded, closeTask == nil else { return }

        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Dwell.close)
            guard !Task.isCancelled else { return }
            self?.collapseIfIdle()
        }
    }

    func expand() {
        openTask = nil
        guard !isExpanded else { return }
        withAnimation(Motion.open) {
            isExpanded = true
            isHinting = false
        }
    }

    func collapse() {
        openTask?.cancel()
        closeTask?.cancel()
        spotlightTask?.cancel()
        openTask = nil
        closeTask = nil
        spotlightTask = nil
        if deviceSpotlight != nil { deviceSpotlight = nil }
        withAnimation(Motion.close) {
            isExpanded = false
            isHinting = false
        }
    }

    /// Honours anything currently holding the panel open.
    private func collapseIfIdle() {
        closeTask = nil
        // A spotlight opened itself and will close itself. Without this, moving
        // the pointer anywhere kills the card 350ms in — the notch was never
        // hovered, so the usual exit rule fires immediately.
        guard !isInteractionLocked, !isDropTargeted, deviceSpotlight == nil else { return }
        collapse()
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }

    func select(_ tab: NotchTab) {
        guard tab != selectedTab else { return }
        withAnimation(Motion.content) { selectedTab = tab }
    }

    // MARK: Spotlight

    /// Throw the panel open for a device, the way a phone does when the case
    /// opens, then bow out on its own.
    func spotlight(_ device: BluetoothDevice, for duration: Duration = .milliseconds(7200)) {
        spotlightTask?.cancel()
        dismissTransient()

        withAnimation(Motion.open) {
            deviceSpotlight = device
            isExpanded = true
            isHinting = false
        }

        spotlightTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.endSpotlight()
        }
    }

    /// Updates the card in place as battery figures arrive, without restarting
    /// the entrance animation or its dismissal.
    func refreshSpotlight(_ device: BluetoothDevice) {
        guard deviceSpotlight?.address == device.address else { return }
        withAnimation(Motion.content) { deviceSpotlight = device }
    }

    func endSpotlight() {
        spotlightTask?.cancel()
        spotlightTask = nil
        guard deviceSpotlight != nil else { return }

        withAnimation(Motion.close) { deviceSpotlight = nil }

        // If they've reached for it, it's theirs now — leave it open.
        guard !isPointerInside, !isInteractionLocked else { return }
        collapse()
    }

    // MARK: Transient activities

    /// Show a toast or level bar, then hand the pill back to whatever was there.
    func present(_ activity: TransientActivity) {
        let refresh = transient.map(activity.replacesInPlace) ?? false
        transientTask?.cancel()

        withAnimation(refresh ? Motion.track : Motion.activity) {
            transient = activity
        }

        transientTask = Task { [weak self] in
            try? await Task.sleep(for: activity.lifetime)
            guard !Task.isCancelled else { return }
            self?.dismissTransient()
        }
    }

    func dismissTransient() {
        transientTask = nil
        guard transient != nil else { return }
        withAnimation(Motion.activity) { transient = nil }
    }
}
