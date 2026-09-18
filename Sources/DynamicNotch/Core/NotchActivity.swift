import SwiftUI

/// A system level the notch can visualise as an inline bar.
enum LevelKind: String, Equatable, Sendable {
    case volume, brightness, keyboardBrightness

    var symbol: String {
        switch self {
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .keyboardBrightness: "light.panel.fill"
        }
    }

    /// Volume swaps its glyph as it falls, the way the system HUD does.
    func symbol(value: Double, muted: Bool) -> String {
        guard self == .volume else { return symbol }
        if muted || value <= 0.001 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var tint: Color {
        switch self {
        case .volume: .white
        case .brightness: Color(red: 1.0, green: 0.85, blue: 0.35)
        case .keyboardBrightness: Color(red: 0.55, green: 0.80, blue: 1.0)
        }
    }
}

struct LevelActivity: Equatable, Sendable {
    var kind: LevelKind
    var value: Double
    var isMuted: Bool = false
}

/// A one-shot toast: charger plugged in, AirPods connected, file stashed.
struct EventActivity: Equatable, Identifiable, Sendable {
    var id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    /// Optional 0…1 meter drawn beside the glyph (battery charge, for instance).
    var meter: Double?
    /// Overrides the default dwell — for moments worth lingering on.
    var duration: Duration?
}

/// Something that takes over the pill briefly and then hands it back.
enum TransientActivity: Equatable, Identifiable {
    case level(LevelActivity)
    case event(EventActivity)

    var id: String {
        switch self {
        case .level(let l): "level.\(l.kind.rawValue)"
        case .event(let e): "event.\(e.id)"
        }
    }

    /// How long it stays before the pill reverts to whatever was underneath.
    var lifetime: Duration {
        switch self {
        case .level: .milliseconds(1400)
        case .event(let event): event.duration ?? .milliseconds(2600)
        }
    }

    /// Later arrivals of the same kind refresh in place instead of re-animating.
    func replacesInPlace(_ other: TransientActivity) -> Bool {
        switch (self, other) {
        case (.level(let a), .level(let b)): a.kind == b.kind
        default: false
        }
    }

    /// Width units (of `NotchLayout.accessoryWidth`) this needs in the closed pill.
    var accessoryUnits: Int {
        switch self {
        case .level: 4
        case .event: 5
        }
    }
}
