import AppKit
import SwiftUI

/// Watches the screen lock.
///
/// macOS broadcasts `com.apple.screenIsLocked` / `screenIsUnlocked` to anyone
/// listening — no permission, no polling.
///
/// **What can and can't be drawn while locked.** The login window is not an
/// app window — it's drawn by `loginwindow` at the shielding level, above
/// everything, and app windows aren't composited over it at all. That's a
/// deliberate security boundary: an app that could paint over the lock screen
/// could paint a convincing fake password box. So no app can show a padlock
/// *during* the lock, this one included.
///
/// What is actually visible is the edges: the padlock lands in the pill a beat
/// before the screen goes (see `QuickActionsService.lockScreen`), and springs
/// open with a greeting the instant you're back.
///
/// The welcome fires on *any* signal that the session came back, and never
/// depends on having seen the matching lock — the app may have launched while
/// locked, or missed the notification, and "I didn't see you leave" is no
/// reason to skip the greeting. macOS often sends more than one such signal, so
/// a short window keeps it from playing twice.
@MainActor
final class SessionService {
    private let model: NotchViewModel
    private var distributed: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Guards against the several notifications macOS sends for one return.
    private var lastWelcome: Date = .distantPast

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        let center = DistributedNotificationCenter.default()

        distributed.append(
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.locked() }
            }
        )
        distributed.append(
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.unlocked() }
            }
        )

        // Fast user switching leaves the session inactive without "locking" it.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspace.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.locked() }
            }
        )
        for name in [
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
        ] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        // Waking is only a welcome if we were actually away.
                        guard let self, self.model.isLocked else { return }
                        self.unlocked()
                    }
                }
            )
        }
    }

    func stop() {
        // Each token belongs to the centre that issued it.
        let center = DistributedNotificationCenter.default()
        distributed.forEach(center.removeObserver)
        distributed.removeAll()

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()
    }

    private func locked() {
        guard !model.isLocked else { return }
        // Fold away first: nothing of ours should be mid-animation behind the
        // login window, and nothing should be waiting open when you come back.
        model.collapse()
        model.dismissTransient()
        withAnimation(Motion.pill) { model.isLocked = true }
        Log.system.info("screen locked")
    }

    private func unlocked() {
        if model.isLocked {
            withAnimation(Motion.pill) { model.isLocked = false }
        }
        Log.system.info("screen unlocked")

        // No delay: this should be on screen as the desktop arrives, not after
        // it. It runs long enough that catching the first frames mid-fade
        // doesn't matter.
        guard Date.now.timeIntervalSince(lastWelcome) > 3 else { return }
        lastWelcome = .now

        model.present(.event(EventActivity(
            symbol: "lock.open.fill",
            tint: .white,
            title: "Unlocked",
            detail: Self.greeting(),
            duration: .milliseconds(3400)
        )))
    }

    private static func greeting() -> String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5 ..< 12: "Good morning"
        case 12 ..< 17: "Good afternoon"
        case 17 ..< 22: "Good evening"
        default: "Welcome back"
        }
    }
}
