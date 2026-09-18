import Foundation
import Testing
@testable import DynamicNotch

/// Fixtures mirror what `system_profiler SPBluetoothDataType -json` really
/// returns on macOS 27, AirPods Pro included.
@Suite("Bluetooth")
struct BluetoothTests {
    private var sample: [String: Any] {
        [
            "SPBluetoothDataType": [[
                "device_connected": [[
                    "Sachin's AirPods Pro": [
                        "device_address": "74:77:86:0A:D8:B8",
                        "device_batteryLevelCase": "65%",
                        "device_batteryLevelLeft": "82%",
                        "device_batteryLevelRight": "81%",
                        "device_minorType": "Headphones",
                    ],
                ]],
                "device_not_connected": [
                    ["MX Master 3S": [
                        "device_address": "D5:52:12:59:0B:2F",
                        "device_minorType": "Mouse",
                    ]],
                    ["MX KEYS S": [
                        "device_address": "DC:06:78:20:25:09",
                        "device_minorType": "Keyboard",
                    ]],
                ],
            ]],
        ]
    }

    @Test("AirPods report three separate charges")
    func airPodsBatteryIsParsed() throws {
        let devices = BluetoothService.parse(sample)
        let pods = try #require(devices.first { $0.name.contains("AirPods") })

        #expect(pods.isConnected)
        #expect(pods.kind == .airpodsPro)
        #expect(pods.batteryLeft == 82)
        #expect(pods.batteryRight == 81)
        #expect(pods.batteryCase == 65)
        // The headline is the lowest thing in your ear — the case doesn't count,
        // because a charged case doesn't help you mid-call.
        #expect(pods.headlineBattery == 81)
    }

    @Test("Disconnected devices come through, without invented battery levels")
    func disconnectedDevicesParsed() throws {
        let devices = BluetoothService.parse(sample)
        let mouse = try #require(devices.first { $0.name == "MX Master 3S" })

        #expect(!mouse.isConnected)
        #expect(mouse.kind == .mouse)
        #expect(!mouse.hasAnyBattery)
        #expect(mouse.headlineBattery == nil)
    }

    @Test("Connected devices sort ahead of the rest")
    func connectedSortFirst() {
        let devices = BluetoothService.parse(sample)
        #expect(devices.count == 3)
        #expect(devices.first?.isConnected == true)
        #expect(devices.last?.isConnected == false)
    }

    @Test("Percentages arrive as strings and come out as numbers")
    func percentParsing() {
        #expect(BluetoothService.percent("82%") == 82)
        #expect(BluetoothService.percent(" 7% ") == 7)
        #expect(BluetoothService.percent(100) == 100)
        #expect(BluetoothService.percent(nil) == nil)
        #expect(BluetoothService.percent("unknown") == nil)
    }

    @Test("Device kind comes from the name first, then the type")
    func kindInference() {
        #expect(BluetoothDevice.Kind.infer(name: "Sachin's AirPods Pro", minorType: "Headphones") == .airpodsPro)
        #expect(BluetoothDevice.Kind.infer(name: "AirPods Max", minorType: nil) == .airpodsMax)
        #expect(BluetoothDevice.Kind.infer(name: "AirPods", minorType: nil) == .airpods)
        // All AirPods report the same device class, so the name is the only tell.
        #expect(BluetoothDevice.Kind.infer(name: "Studio Buds", minorType: "Headphones") == .headphones)
        #expect(BluetoothDevice.Kind.infer(name: "MX KEYS S", minorType: "Keyboard") == .keyboard)
        #expect(BluetoothDevice.Kind.infer(name: "Something", minorType: nil) == .other)
    }

    @Test("Only earpieces are treated as things that can run out mid-use")
    func earpieceKinds() {
        #expect(BluetoothDevice.Kind.airpodsPro.hasEarpieces)
        #expect(!BluetoothDevice.Kind.keyboard.hasEarpieces)
    }

    @Test("Junk in, nothing out")
    func malformedInput() {
        #expect(BluetoothService.parse(nil).isEmpty)
        #expect(BluetoothService.parse([:]).isEmpty)
        #expect(BluetoothService.parse(["SPBluetoothDataType": "nonsense"]).isEmpty)
        // An entry with no address can't be acted on, so it's dropped.
        #expect(BluetoothService.parse([
            "SPBluetoothDataType": [["device_connected": [["Ghost": ["device_minorType": "Mouse"]]]]],
        ]).isEmpty)
    }
}

@Suite("Spotlight")
struct SpotlightTests {
    @MainActor
    private func model() -> NotchViewModel {
        NotchViewModel(metrics: NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 185, height: 32),
            notchCenterX: 756,
            isPhysical: true
        ))
    }

    private let pods = BluetoothDevice(
        address: "74:77:86:0A:D8:B8",
        name: "AirPods Pro",
        kind: .airpodsPro,
        isConnected: true,
        batteryLeft: 82,
        batteryRight: 81,
        batteryCase: 65
    )

    @Test("A spotlight throws the panel open by itself")
    @MainActor
    func spotlightExpands() {
        let model = model()
        #expect(!model.isExpanded)

        model.spotlight(pods)
        #expect(model.isExpanded)
        #expect(model.deviceSpotlight?.address == pods.address)
        #expect(model.mode == .expanded)
    }

    @Test("Battery arriving late updates the card without reopening it")
    @MainActor
    func lateBatteryUpdatesInPlace() {
        let model = model()
        var bare = pods
        bare.batteryLeft = nil
        bare.batteryRight = nil
        bare.batteryCase = nil

        model.spotlight(bare)
        #expect(model.deviceSpotlight?.hasAnyBattery == false)

        model.refreshSpotlight(pods)
        #expect(model.deviceSpotlight?.batteryLeft == 82)
        #expect(model.isExpanded)
    }

    @Test("An update for a different device is ignored")
    @MainActor
    func refreshIgnoresOtherDevices() {
        let model = model()
        model.spotlight(pods)

        var other = pods
        other.address = "AA:BB:CC:DD:EE:FF"
        other.name = "Someone else's"
        model.refreshSpotlight(other)

        #expect(model.deviceSpotlight?.name == "AirPods Pro")
    }

    @Test("Ending the spotlight closes the panel it opened")
    @MainActor
    func endingClosesUp() {
        let model = model()
        model.spotlight(pods)
        model.endSpotlight()

        #expect(model.deviceSpotlight == nil)
        #expect(!model.isExpanded)
    }

    @Test("A card you've reached for stays open when its time is up")
    @MainActor
    func pointerKeepsItOpen() {
        let model = model()
        model.spotlight(pods)
        // The pointer arrived while the card was showing.
        model.isPointerInside = true
        model.endSpotlight()

        // The card itself goes; the panel stays, because it's yours now.
        #expect(model.deviceSpotlight == nil)
        #expect(model.isExpanded)
    }

    @Test("Collapsing for any other reason doesn't strand the card")
    @MainActor
    func collapseClearsTheCard() {
        let model = model()
        model.spotlight(pods)
        model.collapse()

        #expect(model.deviceSpotlight == nil)
        #expect(!model.isExpanded)
    }

    @Test("Only things you wear are worth interrupting for")
    func onlyEarpiecesInterrupt() {
        #expect(BluetoothDevice.Kind.infer(name: "AirPods Pro", minorType: nil).hasEarpieces)
        #expect(BluetoothDevice.Kind.infer(name: "AirPods Max", minorType: nil).hasEarpieces)
        // A keyboard reconnecting should never take over the screen.
        #expect(!BluetoothDevice.Kind.infer(name: "MX KEYS S", minorType: "Keyboard").hasEarpieces)
        #expect(!BluetoothDevice.Kind.infer(name: "MX Master 3S", minorType: "Mouse").hasEarpieces)
    }
}
