import AppKit
import SwiftUI

/// Keeps the notch out of the menu bar's way.
///
/// The moment any app starts tracking a menu, the notch folds shut and stops
/// answering the pointer until tracking ends — so it can never unfurl on top of
/// the menu you are reading, and brushing past it on the way to the menu bar
/// costs you nothing.
///
/// **Not covering the icons.** macOS won't tell an app where other apps' status
/// items are — but it will tell us where *ours* is, and the status bar stacks
/// right to left with the newest item furthest left. Ours is therefore at or
/// very near the left end of the row, which makes its left edge a workable
/// stand-in for "where the icons begin". The closed pill refuses to spread past
/// it. Imperfect: an app that launches after us takes that spot, and then its
/// icon is the one at risk. It is measured live rather than assumed, so it
/// follows icons appearing and disappearing.
///
/// A note on what is deliberately *not* here: reserving space with an empty
/// status item. It reads like the obvious fix, but the status bar stacks items
/// right-to-left, so a spacer only ever pushes its neighbours further left —
/// deeper under the notch — and measuring one in place confirmed it grows
/// leftward *behind* the notch rather than holding anything open. It would have
/// cost ~85pt of menu bar and bought nothing. Surfacing the items macOS has
/// already hidden needs the Accessibility API, which is a bigger, opt-in job.
@MainActor
final class MenuBarGuard {
    private let model: NotchViewModel
    private let settings: NotchSettings
    private var observers: [NSObjectProtocol] = []
    private var measureTask: Task<Void, Never>?

    /// Our own menu bar icon, used as a ruler.
    weak var statusItem: NSStatusItem?

    init(model: NotchViewModel, settings: NotchSettings) {
        self.model = model
        self.settings = settings
    }

    func start() {
        measureTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.measureMenuBar()
                // Icons come and go rarely; this only reads one window frame.
                try? await Task.sleep(for: .seconds(2))
            }
        }

        let center = DistributedNotificationCenter.default()
        let begin = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
        let end = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")

        observers.append(
            center.addObserver(forName: begin, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.settings.yieldToMenus else { return }
                    self.model.isMenuBarBusy = true
                    self.model.collapse()
                }
            }
        )
        observers.append(
            center.addObserver(forName: end, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.isMenuBarBusy = false }
            }
        )
    }

    /// Where the status icons begin, as best we can tell.
    private func measureMenuBar() {
        guard let frame = statusItem?.button?.window?.frame, frame.minX > 1 else { return }
        guard let screen = model.metrics.screenFrame as CGRect?,
              frame.minX < screen.maxX
        else { return }

        if let current = model.menuBarLeftEdge, abs(current - frame.minX) < 2 { return }
        model.menuBarLeftEdge = frame.minX
        Log.window.info("menu bar icons begin at x=\(frame.minX, format: .fixed(precision: 1))")
    }

    func stop() {
        measureTask?.cancel()
        measureTask = nil
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }
}
