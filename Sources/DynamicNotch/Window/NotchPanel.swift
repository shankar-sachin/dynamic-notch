import AppKit

/// A borderless, non-activating panel that floats above the menu bar.
///
/// Non-activating matters: clicking a transport button must not yank focus out
/// of whatever you were typing in.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = Self.restingLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // The notch is furniture, not a document — keep it out of window lists.
        isExcludedFromWindowsMenu = true
        titlebarAppearsTransparent = true
        // Always dark: the panel is a black object, never a themed one.
        appearance = NSAppearance(named: .darkAqua)
    }

    /// Ordinary level: above the menu bar, below everything the system owns.
    static let restingLevel = NSWindow.Level.statusBar + 2

    // Deliberately absent: a "draw over the lock screen" mode.
    //
    // It was tried — the panel was raised to `CGShieldingWindowLevel() + 1`,
    // above `loginwindow`'s shield, which is the highest level there is — and
    // nothing appeared. The lock screen isn't an app window this one can
    // out-rank; it's a separate secure context, and app windows are not
    // composited into it at all. That's the same boundary that stops an app
    // drawing a convincing fake password box, so it isn't going to move.
    //
    // The padlock therefore lives at the edges of the lock instead: shown for a
    // beat before the screen goes, and springing open when you come back. See
    // `SessionService`.

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}
