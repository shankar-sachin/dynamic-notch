import AppKit
import SwiftUI

/// Owns the panel, keeps it glued to the notch, and turns raw pointer movement
/// into hover intent.
///
/// Hover is done with `NSEvent` monitors rather than tracking areas because the
/// notch has to react while *other* apps are frontmost. Mouse-moved monitors
/// need no Accessibility permission — unlike key monitors — so the app stays
/// prompt-free on first launch.
@MainActor
final class NotchWindowController {
    let model: NotchViewModel

    private var panel: NotchPanel?
    private var container: PassthroughView?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var wasInside = false

    /// Set once the shelf exists, so drops have somewhere to land.
    weak var shelf: ShelfStore?
    /// Services the panel drives directly.
    private let timers: TimerService
    private let stopwatch: StopwatchService
    private let bluetooth: BluetoothService
    private let actions: QuickActionsService

    init(
        model: NotchViewModel,
        timers: TimerService,
        stopwatch: StopwatchService,
        bluetooth: BluetoothService,
        actions: QuickActionsService
    ) {
        self.model = model
        self.timers = timers
        self.stopwatch = stopwatch
        self.bluetooth = bluetooth
        self.actions = actions
    }

    /// The panel's own view, for anchoring the share sheet.
    var anchorView: NSView? { container }

    // MARK: Lifecycle

    func start() {
        buildPanel()
        installMonitors()
        installObservers()
    }

    func stop() {
        monitors.compactMap { $0 }.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.orderOut(nil)
        panel = nil
        container = nil
    }

    // MARK: Panel

    private func buildPanel() {
        let frame = windowFrame()
        let panel = NotchPanel(contentRect: frame)

        let container = PassthroughView(frame: CGRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.interactiveRect = { [weak self] in self?.bodyRectInView() ?? .zero }
        container.dropHandler = self

        let host = NSHostingView(
            rootView: NotchRootView(
                model: model,
                timers: timers,
                stopwatch: stopwatch,
                bluetooth: bluetooth,
                actions: actions
            )
        )
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        // Let the SwiftUI layer paint into the notch without a system backdrop.
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        container.addSubview(host)

        panel.contentView = container
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.container = container
        Log.window.info(
            "notch \(self.model.metrics.notchSize.width, format: .fixed(precision: 1))x\(self.model.metrics.notchSize.height, format: .fixed(precision: 1)) physical=\(self.model.metrics.isPhysical) panel=\(frame.debugDescription, privacy: .public)"
        )
    }

    private func windowFrame() -> CGRect {
        let metrics = model.metrics
        let size = NotchLayout.windowSize(notch: metrics.notchSize)
        return CGRect(
            x: (metrics.notchCenterX - size.width / 2).rounded(),
            y: metrics.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The drawn body, in the container view's (bottom-left origin) coordinates.
    private func bodyRectInView() -> CGRect {
        guard let container else { return .zero }
        let p = model.presentation
        let bounds = container.bounds
        return CGRect(
            x: (bounds.width - p.outerWidth) / 2,
            y: bounds.maxY - p.bodySize.height,
            width: p.outerWidth,
            height: p.bodySize.height
        )
    }

    // MARK: Screen changes

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.relocate() }
            }
        )

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.relocate() }
                }
            )
        }
    }

    /// Re-measure and re-seat the panel: display connected, resolution changed,
    /// woken from sleep, or the menu bar moved to another screen.
    func relocate() {
        guard let screen = NSScreen.notchHost else { return }
        let metrics = NotchMetrics.measure(screen)
        let resized = metrics.notchSize != model.metrics.notchSize
        model.metrics = metrics

        guard let panel else { return }
        if resized {
            panel.setContentSize(NotchLayout.windowSize(notch: metrics.notchSize))
        }
        panel.setFrame(windowFrame(), display: true)
        panel.orderFrontRegardless()
    }

    // MARK: Pointer

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] event in
                let dragging = event.type == .leftMouseDragged
                MainActor.assumeIsolated { self?.pointerMoved(dragging: dragging) }
            } as Any
        )
        monitors.append(
            NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
                self?.pointerMoved(dragging: event.type == .leftMouseDragged)
                return event
            } as Any
        )

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
                MainActor.assumeIsolated { self?.clickedOutside() }
            } as Any
        )
    }

    private func pointerMoved(dragging: Bool) {
        let inside = model.hoverRect.contains(NSEvent.mouseLocation)
        if inside {
            model.pointerEntered(dragging: dragging)
        } else if wasInside || model.isExpanded || model.isHinting {
            model.pointerExited()
        }
        wasInside = inside
    }

    private func clickedOutside() {
        guard model.isExpanded else { return }
        if !model.hoverRect.contains(NSEvent.mouseLocation) {
            model.collapse()
        }
    }
}


// MARK: - Drops

extension NotchWindowController: NotchDropHandling {
    func notchDragEntered(_ pasteboard: NSPasteboard) -> Bool {
        guard let shelf, shelf.canAccept(pasteboard) else { return false }

        if !model.isDropTargeted {
            withAnimation(Motion.activity) { model.isDropTargeted = true }
            model.select(.shelf)
        }
        // A drag is already a commitment, so open faster than a hover would.
        model.pointerEntered(dragging: true)
        return true
    }

    func notchDragExited() {
        guard model.isDropTargeted else { return }
        withAnimation(Motion.activity) { model.isDropTargeted = false }
        model.pointerExited()
    }

    func notchPerformDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard let shelf else { return false }
        withAnimation(Motion.activity) { model.isDropTargeted = false }
        let count = shelf.accept(pasteboard)
        if count > 0 {
            model.select(.shelf)
            model.expand()
        }
        return count > 0
    }
}
