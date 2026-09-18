import AppKit
import SwiftUI

@main
enum DynamicNotchMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Retain the delegate: NSApplication holds it weakly.
        objc_setAssociatedObject(app, "com.sachi.DynamicNotch.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: NotchViewModel!
    private var controller: NotchWindowController!
    private var media: MediaService!
    private var audio: AudioService!
    private var brightness: BrightnessService!
    private var shelf: ShelfStore!
    private var menuBar: MenuBarGuard!
    private var power: PowerService!
    private var devices: BluetoothService!
    private var privacy: PrivacyService!
    private var session: SessionService!
    private var clock: ClockBridge!
    private var timers: TimerService!
    private var stopwatch: StopwatchService!
    private var actions: QuickActionsService!
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem!
    #if DEBUG
    private var debugBridge: DebugBridge?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.notchHost else {
            NSApp.terminate(nil)
            return
        }

        model = NotchViewModel(metrics: .measure(screen))
        timers = TimerService(model: model)
        stopwatch = StopwatchService(model: model)
        actions = QuickActionsService(model: model)
        devices = BluetoothService(model: model)

        controller = NotchWindowController(
            model: model,
            timers: timers,
            stopwatch: stopwatch,
            bluetooth: devices,
            actions: actions
        )
        controller.start()

        shelf = ShelfStore(model: model)
        shelf.restore()
        controller.shelf = shelf
        model.shelfStore = shelf
        model.shareAnchor = { [weak self] in self?.controller.anchorView }

        media = MediaService(model: model)
        media.start()
        model.onRequestMediaAccess = { [weak self] in self?.media.requestAccess() }

        audio = AudioService(model: model)
        audio.start()

        brightness = BrightnessService(model: model)
        brightness.start()

        power = PowerService(model: model)
        power.start()

        devices.start()

        privacy = PrivacyService(model: model)
        privacy.start()

        clock = ClockBridge(model: model)
        clock.start()
        timers.clock = clock

        session = SessionService(model: model)
        session.start()

        buildStatusItem()

        // Built after our own status item so the spacer lands beside the notch.
        menuBar = MenuBarGuard(model: model, settings: .shared)
        menuBar.statusItem = statusItem
        menuBar.start()

        #if DEBUG
        debugBridge = DebugBridge(model: model)
        debugBridge?.onStartTimer = { [weak self] duration in
            self?.timers.start(duration)
        }
        debugBridge?.onClockDiagnose = { [weak self] on in
            self?.clock.diagnose = on
        }
        debugBridge?.onStopwatch = { [weak self] action in
            switch action {
            case "lap": self?.stopwatch.lap()
            case "reset": self?.stopwatch.reset()
            default: self?.stopwatch.toggle()
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        clock?.stop()
        session?.stop()
        privacy?.stop()
        actions?.stop()
        timers?.stop()
        devices?.stop()
        power?.stop()
        menuBar?.stop()
        brightness?.stop()
        audio?.stop()
        media?.stop()
        controller?.stop()
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Dynamic Notch"
        )
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Dynamic Notch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    @objc private func toggleNotch() {
        model.toggle()
    }

    @objc private func openSettings() {
        settingsWindow.show(settings: .shared)
    }
}
