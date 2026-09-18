import AppKit
import SwiftUI

/// Ordinary settings window for an app that otherwise has no windows at all.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: NotchSettings) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Dynamic Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 460, height: 520))

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Open when the pointer reaches the notch", isOn: $settings.hoverToOpen)
                Text("With hover off, click the notch or use the menu bar icon. Dragging files onto it always works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Show in the notch") {
                Toggle("Now Playing", isOn: $settings.showNowPlaying)
                Toggle("Volume", isOn: $settings.showVolumeHUD)
                Toggle("Screen brightness", isOn: $settings.showBrightnessHUD)
                Toggle("Keyboard backlight", isOn: $settings.showKeyboardBacklightHUD)
                Toggle("Charging and battery", isOn: $settings.showPowerEvents)
                Toggle("Bluetooth devices", isOn: $settings.showDeviceEvents)
                Toggle("Open fully when AirPods connect", isOn: $settings.expandForAirPods)
                    .disabled(!settings.showDeviceEvents)
            }

            Section("Menu bar") {
                Toggle("Get out of the way while a menu is open", isOn: $settings.yieldToMenus)
                Text("The notch folds shut the moment you open any menu, so it never lands on top of one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Dynamic Notch")
                        .font(.headline)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
