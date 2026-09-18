#if DEBUG
import AppKit
import SwiftUI

/// Debug-only remote control, so states can be driven from the terminal while
/// building — `notchctl expand`, `notchctl track`, `notchctl level volume 0.6`.
/// Compiled out of release builds entirely.
@MainActor
final class DebugBridge {
    static let notification = Notification.Name("com.sachi.DynamicNotch.debug")

    private let model: NotchViewModel
    private var observer: NSObjectProtocol?
    /// Set by the app delegate so `notchctl timer 30` can drive the real service.
    var onStartTimer: ((TimeInterval) -> Void)?
    var onClockDiagnose: ((Bool) -> Void)?
    var onStopwatch: ((String) -> Void)?

    init(model: NotchViewModel) {
        self.model = model
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Lift a Sendable snapshot out of the notification before hopping.
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { self?.handle(info) }
        }
    }

    private func handle(_ info: [String: String]) {
        switch info["command"] ?? "" {
        case "expand": model.expand()
        case "collapse": model.collapse()
        case "toggle": model.toggle()
        case "tab":
            model.select(NotchTab(rawValue: info["value"] ?? "home") ?? .home)

        case "timer":
            onStartTimer?(Double(info["value"] ?? "30") ?? 30)

        case "airpods":
            let existing = model.bluetooth.first { $0.kind.hasEarpieces }
            model.spotlight(existing ?? BluetoothDevice(
                address: "00:00:00:00:00:00",
                name: info["title"] ?? "AirPods Pro",
                kind: .airpodsPro,
                isConnected: true,
                batteryLeft: 82,
                batteryRight: 81,
                batteryCase: 65
            ))

        case "stopwatch":
            onStopwatch?(info["value"] ?? "toggle")

        case "clockdiag":
            onClockDiagnose?(info["value"] != "false")

        case "clockdump":
            CFPreferencesAppSynchronize("com.apple.mobiletimerd" as CFString)
            let raw = CFPreferencesCopyAppValue(
                "MTTimers" as CFString, "com.apple.mobiletimerd" as CFString
            )
            Log.app.error("MTTimers raw: \(String(describing: raw), privacy: .public)")

        case "mic":
            model.privacy.micInUse = info["value"] != "false"

        case "track":
            model.nowPlaying = NowPlayingSnapshot(
                source: info["value"] == "spotify" ? .spotify : .music,
                title: info["title"] ?? "Everything In Its Right Place",
                artist: info["artist"] ?? "Radiohead",
                album: info["album"] ?? "Kid A",
                isPlaying: info["playing"] != "false",
                duration: 251,
                position: 64,
                sampledAt: .now,
                artwork: Self.demoArtwork(),
                accent: Color(red: 0.36, green: 0.55, blue: 0.95)
            )

        case "notrack":
            model.nowPlaying = nil

        case "level":
            let kind = LevelKind(rawValue: info["value"] ?? "volume") ?? .volume
            model.present(.level(LevelActivity(
                kind: kind,
                value: Double(info["amount"] ?? "0.6") ?? 0.6
            )))

        case "event":
            model.present(.event(EventActivity(
                symbol: info["symbol"] ?? "bolt.fill",
                tint: .green,
                title: info["title"] ?? "Charging",
                detail: info["detail"] ?? "72% · 48m left",
                meter: 0.72
            )))

        case "drop":
            withAnimation(Motion.activity) { model.isDropTargeted = info["value"] != "false" }

        default:
            break
        }
    }

    /// A stand-in album cover so layout can be judged without a music app open.
    private static func demoArtwork() -> NSImage {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(
            colors: [
                NSColor(red: 0.38, green: 0.55, blue: 0.98, alpha: 1),
                NSColor(red: 0.62, green: 0.30, blue: 0.86, alpha: 1),
                NSColor(red: 0.95, green: 0.42, blue: 0.40, alpha: 1),
            ]
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 55)
        image.unlockFocus()
        return image
    }
}
#endif
