import AppKit
import ServiceManagement
import SwiftUI

/// User preferences, persisted the moment they change.
@MainActor
@Observable
final class NotchSettings {
    static let shared = NotchSettings()

    var hoverToOpen: Bool { didSet { store(hoverToOpen, "hoverToOpen") } }
    var showNowPlaying: Bool { didSet { store(showNowPlaying, "showNowPlaying") } }
    var showVolumeHUD: Bool { didSet { store(showVolumeHUD, "showVolumeHUD") } }
    var showBrightnessHUD: Bool { didSet { store(showBrightnessHUD, "showBrightnessHUD") } }
    var showKeyboardBacklightHUD: Bool { didSet { store(showKeyboardBacklightHUD, "showKeyboardBacklightHUD") } }
    var showPowerEvents: Bool { didSet { store(showPowerEvents, "showPowerEvents") } }
    var showDeviceEvents: Bool { didSet { store(showDeviceEvents, "showDeviceEvents") } }
    /// Throw the panel open when AirPods connect, rather than just a toast.
    var expandForAirPods: Bool { didSet { store(expandForAirPods, "expandForAirPods") } }
    /// Fold the notch away while a menu is open, so it can never sit on top of one.
    var yieldToMenus: Bool { didSet { store(yieldToMenus, "yieldToMenus") } }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.error("login item failed: \(error.localizedDescription, privacy: .public)")
                launchAtLogin = oldValue
            }
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
        func flag(_ key: String, default value: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? value
        }
        hoverToOpen = flag("hoverToOpen", default: true)
        showNowPlaying = flag("showNowPlaying", default: true)
        showVolumeHUD = flag("showVolumeHUD", default: true)
        showBrightnessHUD = flag("showBrightnessHUD", default: true)
        // Off by default: the keyboard backlight is driven by the ambient light
        // sensor as much as by you, so it's the one HUD that interrupts without
        // being asked. Available for anyone who wants it, but opt-in.
        showKeyboardBacklightHUD = flag("showKeyboardBacklightHUD", default: false)
        showPowerEvents = flag("showPowerEvents", default: true)
        showDeviceEvents = flag("showDeviceEvents", default: true)
        expandForAirPods = flag("expandForAirPods", default: true)
        yieldToMenus = flag("yieldToMenus", default: true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
