import SwiftUI

/// A paired Bluetooth device, as `system_profiler` describes it.
struct BluetoothDevice: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case airpods, airpodsPro, airpodsMax, headphones, speaker
        case keyboard, mouse, trackpad, phone, watch, other

        var symbol: String {
            switch self {
            case .airpods: "airpods.gen3"
            case .airpodsPro: "airpodspro"
            case .airpodsMax: "airpodsmax"
            case .headphones: "headphones"
            case .speaker: "hifispeaker.fill"
            case .keyboard: "keyboard.fill"
            case .mouse: "magicmouse.fill"
            case .trackpad: "trackpad.fill"
            case .phone: "iphone"
            case .watch: "applewatch"
            case .other: "dot.radiowaves.left.and.right"
            }
        }

        /// True when the device reports separate buds and a case.
        var hasEarpieces: Bool {
            self == .airpods || self == .airpodsPro || self == .airpodsMax
        }

        static func infer(name: String, minorType: String?) -> Kind {
            let lower = name.lowercased()
            if lower.contains("airpods max") { return .airpodsMax }
            if lower.contains("airpods pro") { return .airpodsPro }
            if lower.contains("airpods") { return .airpods }
            if lower.contains("beats") || lower.contains("headphone") { return .headphones }

            switch minorType?.lowercased() {
            case "headphones": return .headphones
            case "speaker": return .speaker
            case "keyboard": return .keyboard
            case "mouse": return .mouse
            case "trackpad": return .trackpad
            case "smartphone", "phone": return .phone
            default: return .other
            }
        }
    }

    var address: String
    var name: String
    var kind: Kind
    var isConnected: Bool
    var batteryLeft: Int?
    var batteryRight: Int?
    var batteryCase: Int?
    var batterySingle: Int?

    var id: String { address }

    /// The number worth worrying about: the lowest thing you're wearing.
    var headlineBattery: Int? {
        let worn = [batteryLeft, batteryRight, batterySingle].compactMap { $0 }
        return worn.min()
    }

    var hasAnyBattery: Bool {
        batteryLeft != nil || batteryRight != nil || batteryCase != nil || batterySingle != nil
    }

    var symbol: String { kind.symbol }
}
