import AppKit
import IOBluetooth
import SwiftUI

/// Bluetooth devices: what's connected, how much charge it has left, and
/// connecting or disconnecting it without leaving the notch.
///
/// Two sources, because neither is enough alone:
///  * **IOBluetooth** gives instant connect/disconnect callbacks and the ability
///    to open and close connections, but will not tell you a battery level.
///  * **`system_profiler SPBluetoothDataType`** knows the battery of every
///    connected device — including AirPods' left, right and case separately —
///    but has to be asked. It costs ~120ms, so it's asked on connection changes,
///    when you open the panel, and occasionally while something is connected.
///
/// Neither needs a permission prompt: the CoreBluetooth prompt is for scanning
/// for BLE peripherals, which this deliberately never does.
@MainActor
final class BluetoothService: NSObject {
    private let model: NotchViewModel
    private var connectNotification: IOBluetoothUserNotification?
    private var refreshTask: Task<Void, Never>?
    /// Devices already connected at launch: not news.
    private var known: Set<String> = []
    /// Devices we've already warned about, so it's said once per connection.
    private var warnedLowBattery: Set<String> = []

    init(model: NotchViewModel) {
        self.model = model
        super.init()
    }

    func start() {
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        where device.isConnected() {
            known.insert(device.addressString ?? "")
        }

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Battery moves slowly; this is a background truth, not a feed.
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        connectNotification?.unregister()
        connectNotification = nil
    }

    // MARK: Inventory

    func refresh() async {
        let devices = await Self.inventory()
        guard !devices.isEmpty || !model.bluetooth.isEmpty else { return }
        if devices.count != model.bluetooth.count {
            let connected = devices.filter(\.isConnected).count
            Log.system.info("bluetooth: \(devices.count) paired, \(connected) connected")
        }
        withAnimation(Motion.content) { model.bluetooth = devices }
        checkLowBattery(devices)
    }

    /// Runs `system_profiler` off the main thread and parses what comes back.
    private nonisolated static func inventory() async -> [BluetoothDevice] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: parse(runProfiler()))
            }
        }
    }

    private nonisolated static func runProfiler() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    nonisolated static func parse(_ json: [String: Any]?) -> [BluetoothDevice] {
        guard let root = json,
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var devices: [BluetoothDevice] = []
        for section in sections {
            devices += entries(section["device_connected"], connected: true)
            devices += entries(section["device_not_connected"], connected: false)
        }
        // Connected first, then alphabetical — a stable order the eye can track.
        return devices.sorted {
            $0.isConnected == $1.isConnected
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.isConnected
        }
    }

    /// Each entry is a single-key dictionary: the device name maps to its detail.
    private nonisolated static func entries(_ value: Any?, connected: Bool) -> [BluetoothDevice] {
        guard let list = value as? [[String: Any]] else { return [] }

        return list.compactMap { wrapper in
            guard let (name, raw) = wrapper.first,
                  let detail = raw as? [String: Any],
                  let address = detail["device_address"] as? String
            else { return nil }

            return BluetoothDevice(
                address: address,
                name: name,
                kind: .infer(name: name, minorType: detail["device_minorType"] as? String),
                isConnected: connected,
                batteryLeft: percent(detail["device_batteryLevelLeft"]),
                batteryRight: percent(detail["device_batteryLevelRight"]),
                batteryCase: percent(detail["device_batteryLevelCase"]),
                batterySingle: percent(detail["device_batteryLevelMain"])
                    ?? percent(detail["device_batteryLevel"])
            )
        }
    }

    /// Levels arrive as strings like `"82%"`.
    nonisolated static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return value as? Int }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    // MARK: Connecting

    func toggleConnection(_ device: BluetoothDevice) {
        let address = device.address
        let shouldConnect = !device.isConnected

        model.present(.event(EventActivity(
            symbol: device.symbol,
            tint: .white,
            title: device.name,
            detail: shouldConnect ? "Connecting…" : "Disconnecting…"
        )))

        Task.detached(priority: .userInitiated) {
            // These block for as long as the radio takes; never on the main thread.
            guard let target = IOBluetoothDevice(addressString: address) else { return }
            if shouldConnect {
                target.openConnection()
            } else {
                target.closeConnection()
            }
            try? await Task.sleep(for: .milliseconds(900))
            await self.refresh()
        }
    }

    // MARK: Events

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        let address = device.addressString ?? ""
        let name = device.name ?? device.nameOrAddress ?? "Device"
        let isNew = !known.contains(address)
        known.insert(address)
        warnedLowBattery.remove(address)

        device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )

        Log.system.info("bluetooth connected: \(name, privacy: .public)")
        guard model.settings.showDeviceEvents, isNew else { return }

        Task { [weak self] in
            guard let self else { return }

            // Earpieces get the full card, the way a phone does when the case
            // opens. Everything else gets a toast — throwing the whole panel
            // open because a keyboard woke up would be obnoxious.
            let earlyMatch = model.bluetooth.first { $0.address == address }
            let isEarpiece = earlyMatch?.kind.hasEarpieces
                ?? BluetoothDevice.Kind.infer(name: name, minorType: nil).hasEarpieces

            if isEarpiece, model.settings.expandForAirPods {
                // Open immediately on the connection, then fill the battery in
                // when it arrives — waiting first would make the notch feel slow
                // at the one moment it should feel instant.
                model.spotlight(
                    earlyMatch ?? BluetoothDevice(
                        address: address,
                        name: name,
                        kind: .infer(name: name, minorType: nil),
                        isConnected: true
                    )
                )
            }

            // Charge isn't reported the instant a device connects.
            try? await Task.sleep(for: .milliseconds(1100))
            await refresh()
            let match = model.bluetooth.first { $0.address == address }

            if isEarpiece, model.settings.expandForAirPods {
                if let match { model.refreshSpotlight(match) }
                return
            }

            model.present(.event(EventActivity(
                symbol: match?.symbol ?? "dot.radiowaves.left.and.right",
                tint: .white,
                title: name,
                detail: match?.headlineBattery.map { "Connected · \($0)%" } ?? "Connected",
                meter: match?.headlineBattery.map { Double($0) / 100 }
            )))
        }
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        notification.unregister()
        let address = device.addressString ?? ""
        known.remove(address)
        warnedLowBattery.remove(address)

        Task { [weak self] in
            await self?.refresh()
        }

        guard model.settings.showDeviceEvents else { return }
        model.present(.event(EventActivity(
            symbol: "dot.radiowaves.left.and.right",
            tint: .white.opacity(0.7),
            title: device.name ?? "Device",
            detail: "Disconnected"
        )))
    }

    /// One warning per connection, for the thing in your ears.
    private func checkLowBattery(_ devices: [BluetoothDevice]) {
        guard model.settings.showDeviceEvents else { return }

        for device in devices where device.isConnected && device.kind.hasEarpieces {
            guard let level = device.headlineBattery, level <= 15 else { continue }
            guard !warnedLowBattery.contains(device.address) else { continue }
            warnedLowBattery.insert(device.address)

            model.present(.event(EventActivity(
                symbol: device.symbol,
                tint: .orange,
                title: device.name,
                detail: "Low battery · \(level)%",
                meter: Double(level) / 100
            )))
        }
    }
}
