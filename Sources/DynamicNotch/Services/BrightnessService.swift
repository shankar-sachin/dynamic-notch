import AppKit
import CoreGraphics

/// Screen and keyboard backlight levels.
///
/// macOS publishes no notification for either, so this polls — but cheaply and
/// adaptively: a lazy heartbeat that speeds up for a couple of seconds once
/// something moves, then settles back down.
///
/// The interesting problem is telling *you* apart from the *light sensor*. Both
/// move these levels, and the keyboard backlight especially is adjusted
/// constantly as the room changes — surfacing a HUD for that is maddening.
///
/// A size threshold alone isn't enough, because an ambient ramp can clear any
/// threshold if the light changes fast. The shape of the change is the real
/// tell: the sensor *ramps*, nudging the level on tick after tick, while a key
/// press is a single jump out of stillness. So a change only counts if the
/// previous tick was quiet. Once that's fired, a 1.6s window lets a held key
/// keep updating the bar smoothly.
///
/// Waking is the exception that defeats all of that. Both levels go from nothing
/// to their target in one step when the lid opens or the display comes back —
/// a perfect jump out of perfect stillness, and exactly what a key press looks
/// like. So after any wake the next few seconds are absorbed: the new levels are
/// adopted as the baseline without a word.
@MainActor
final class BrightnessService {
    private let model: NotchViewModel

    /// One tracked level, with just enough history to spot a ramp.
    private struct Channel {
        var level: Float?
        var lastDelta: Float = 0
    }

    private var task: Task<Void, Never>?
    private var display = Channel()
    private var keyboardChannel = Channel()
    private var alertUntil: Date = .distantPast
    /// Changes before this moment are treated as the machine waking, not you.
    private var settleUntil: Date = .distantPast
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    /// Key steps are 1/16 = 0.0625. The screen is steadier than the keyboard
    /// backlight, so it can afford a finer threshold.
    private let displayThreshold: Float = 0.025
    private let keyboardThreshold: Float = 0.045
    private let idleInterval = Duration.milliseconds(400)
    private let alertInterval = Duration.milliseconds(90)

    private let getDisplayBrightness: ((UInt32, UnsafeMutablePointer<Float>) -> Int32)?
    private let keyboard: KeyboardBrightnessReading?

    init(model: NotchViewModel) {
        self.model = model

        // DisplayServices is private but unrestricted: no entitlement, no prompt.
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ), let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
            let function = unsafeBitCast(symbol, to: GetBrightness.self)
            getDisplayBrightness = { function($0, $1) }
        } else {
            getDisplayBrightness = nil
            Log.system.error("DisplayServices unavailable; screen brightness HUD disabled")
        }

        keyboard = KeyboardBrightnessReading()
    }

    func start() {
        display.level = readDisplay()
        keyboardChannel.level = keyboard?.read()
        observeWake()

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                tick()
                try? await Task.sleep(for: Date.now < alertUntil ? alertInterval : idleInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        // Each token belongs to the centre that issued it.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributed.removeObserver)
        distributedObservers.removeAll()
    }

    /// Everything that means "the machine just came back".
    private func observeWake() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.settle() }
                }
            )
        }
        distributedObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.settle() }
            }
        )
    }

    private func settle() {
        settleUntil = .now.addingTimeInterval(4)
        Log.system.info("brightness settling after wake")
    }

    // MARK: Polling

    private func tick() {
        if model.settings.showBrightnessHUD, let level = readDisplay() {
            report(level, into: &display, kind: .brightness, threshold: displayThreshold)
        } else if let level = readDisplay() {
            display.level = level
        }

        if model.settings.showKeyboardBacklightHUD, let level = keyboard?.read() {
            report(level, into: &keyboardChannel, kind: .keyboardBrightness, threshold: keyboardThreshold)
        } else if let level = keyboard?.read() {
            keyboardChannel.level = level
        }
    }

    private func report(_ level: Float, into channel: inout Channel, kind: LevelKind, threshold: Float) {
        guard let old = channel.level else {
            channel.level = level
            return
        }
        let delta = level - old
        defer {
            channel.level = level
            channel.lastDelta = delta
        }

        guard abs(delta) > threshold else { return }

        // Just woken: adopt whatever the levels have become, say nothing.
        guard Date.now >= settleUntil else { return }

        // Mid-gesture the bar is already up, so let every step through and keep
        // it smooth. Otherwise demand stillness before the jump — that's what
        // separates a key press from the light sensor ramping.
        let isMidGesture = Date.now < alertUntil
        if !isMidGesture {
            guard abs(channel.lastDelta) < threshold * 0.4 else { return }
        }

        alertUntil = .now.addingTimeInterval(1.6)
        model.present(.level(LevelActivity(kind: kind, value: Double(level))))
    }

    private func readDisplay() -> Float? {
        guard let getDisplayBrightness else { return nil }
        var value: Float = 0
        let display = displayID()
        guard getDisplayBrightness(display, &value) == 0, value >= 0 else { return nil }
        return value
    }

    /// Follow the screen the notch lives on, not whichever display is "main".
    private func displayID() -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.notchHost,
           let number = screen.deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }
}

/// Keyboard backlight, read through CoreBrightness.
///
/// Entirely optional: Macs without a backlit keyboard — and any future macOS
/// that drops the class — simply never produce a reading, and the HUD for it
/// quietly doesn't exist.
private struct KeyboardBrightnessReading {
    @objc private protocol KeyboardBrightnessClient {
        func brightnessForKeyboard(_ keyboard: UInt64) -> Float
    }

    private let client: KeyboardBrightnessClient
    private let keyboardID: UInt64 = 1

    init?() {
        guard dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_NOW
        ) != nil else { return nil }
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            return nil
        }
        let instance = type.init()
        guard instance.responds(to: NSSelectorFromString("brightnessForKeyboard:")) else {
            return nil
        }
        client = unsafeBitCast(instance, to: KeyboardBrightnessClient.self)
    }

    func read() -> Float? {
        let value = client.brightnessForKeyboard(keyboardID)
        return value >= 0 ? value : nil
    }
}
