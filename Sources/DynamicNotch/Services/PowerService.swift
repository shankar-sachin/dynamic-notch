import AppKit
import IOKit.ps
import SwiftUI

/// Charger and battery moments.
///
/// Driven by IOKit's power-source run loop source, so it costs nothing until
/// something actually happens. Only *transitions* are announced — a toast per
/// event, never a running commentary on the battery percentage.
@MainActor
final class PowerService {
    struct Reading: Equatable {
        var percent: Double
        var isPlugged: Bool
        var isCharging: Bool
        var isCharged: Bool
        var minutesRemaining: Int?
    }

    private let model: NotchViewModel
    private var source: CFRunLoopSource?
    private var last: Reading?
    /// Low-battery thresholds already announced this discharge cycle.
    private var announcedLow: Set<Int> = []

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        last = Self.read()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ pointer in
            guard let pointer else { return }
            let service = Unmanaged<PowerService>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated { service.powerChanged() }
        }, context)?.takeRetainedValue() else {
            Log.system.error("power source notifications unavailable")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        source = nil
    }

    // MARK: Transitions

    private func powerChanged() {
        guard let reading = Self.read() else { return }
        defer { last = reading }
        guard let previous = last, model.settings.showPowerEvents else { return }

        if reading.isPlugged != previous.isPlugged {
            announcedLow.removeAll()
            model.present(.event(reading.isPlugged ? pluggedIn(reading) : unplugged(reading)))
            return
        }

        if reading.isCharged, !previous.isCharged, reading.isPlugged {
            model.present(.event(EventActivity(
                symbol: "battery.100percent.bolt",
                tint: .green,
                title: "Charged",
                detail: "100%",
                meter: 1
            )))
            return
        }

        guard !reading.isPlugged else { return }
        for threshold in [20, 10, 5] where reading.percent <= Double(threshold)
            && previous.percent > Double(threshold)
            && !announcedLow.contains(threshold)
        {
            announcedLow.insert(threshold)
            model.present(.event(EventActivity(
                symbol: "battery.25percent",
                tint: threshold <= 10 ? .red : .orange,
                title: "Low Battery",
                detail: "\(Int(reading.percent))%" + (reading.minutesRemaining.map { " · \(Self.duration($0)) left" } ?? ""),
                meter: reading.percent / 100
            )))
            break
        }
    }

    private func pluggedIn(_ reading: Reading) -> EventActivity {
        EventActivity(
            symbol: "bolt.fill",
            tint: .green,
            title: reading.isCharged ? "Charged" : "Charging",
            detail: "\(Int(reading.percent))%"
                + (reading.minutesRemaining.map { " · \(Self.duration($0)) to full" } ?? ""),
            meter: reading.percent / 100
        )
    }

    private func unplugged(_ reading: Reading) -> EventActivity {
        EventActivity(
            symbol: "battery.50percent",
            tint: reading.percent <= 20 ? .orange : .white,
            title: "On Battery",
            detail: "\(Int(reading.percent))%"
                + (reading.minutesRemaining.map { " · \(Self.duration($0)) left" } ?? ""),
            meter: reading.percent / 100
        )
    }

    // MARK: Reading IOKit

    nonisolated static func read() -> Reading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(1, description[kIOPSMaxCapacityKey] as? Int ?? 100)
            let isPlugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            // IOKit reports -1 while it works out an estimate.
            let rawMinutes = isPlugged
                ? description[kIOPSTimeToFullChargeKey] as? Int
                : description[kIOPSTimeToEmptyKey] as? Int
            let minutes = (rawMinutes ?? -1) > 0 ? rawMinutes : nil

            return Reading(
                percent: Double(current) / Double(maximum) * 100,
                isPlugged: isPlugged,
                isCharging: isCharging,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                minutesRemaining: minutes
            )
        }
        return nil
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
