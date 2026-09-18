import SwiftUI

/// Bluetooth devices, with the charge left in the ones that report it.
struct DevicesPanel: View {
    let model: NotchViewModel
    let bluetooth: BluetoothService

    private var connected: [BluetoothDevice] { model.bluetooth.filter(\.isConnected) }
    private var available: [BluetoothDevice] { model.bluetooth.filter { !$0.isConnected } }

    var body: some View {
        Group {
            if model.bluetooth.isEmpty {
                EmptyPanel(
                    symbol: "dot.radiowaves.left.and.right",
                    title: "No paired devices",
                    detail: "Devices you've paired with this Mac show up here."
                )
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    if connected.isEmpty {
                        Text("Nothing connected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        ForEach(connected.prefix(2)) { device in
                            ConnectedRow(device: device, bluetooth: bluetooth)
                        }
                    }

                    if !available.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(available) { device in
                                    AvailableChip(device: device, bluetooth: bluetooth)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }
            }
        }
        .task {
            // Freshen the moment the panel is looked at.
            await bluetooth.refresh()
        }
    }
}

/// A connected device: what it is, what's left in it, and a way to drop it.
private struct ConnectedRow: View {
    let device: BluetoothDevice
    let bluetooth: BluetoothService

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if device.hasAnyBattery {
                    HStack(spacing: 7) {
                        if device.kind.hasEarpieces {
                            // Buds and case charge separately, so show them so.
                            cell("L", device.batteryLeft)
                            cell("R", device.batteryRight)
                            cell("Case", device.batteryCase, symbol: "case.fill")
                        } else {
                            cell(nil, device.batterySingle ?? device.headlineBattery)
                        }
                    }
                } else {
                    Text("Connected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)

            Button {
                bluetooth.toggleConnection(device)
            } label: {
                Text("Disconnect")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.65))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .glassEffect(Glass.control, in: .capsule)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(Motion.pill) { isHovering = hovering }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(Glass.control, in: .rect(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func cell(_ label: String?, _ level: Int?, symbol: String? = nil) -> some View {
        if let level {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                } else if let label {
                    Text(label)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text("\(level)%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint(level))
            }
        }
    }

    private func tint(_ level: Int) -> Color {
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .white.opacity(0.75)
    }
}

/// A paired but disconnected device — one tap to bring it back.
private struct AvailableChip: View {
    let device: BluetoothDevice
    let bluetooth: BluetoothService

    @State private var isHovering = false

    var body: some View {
        Button {
            bluetooth.toggleConnection(device)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: device.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(device.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isHovering ? 1 : 0.55))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .glassEffect(Glass.control, in: .capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.pill) { isHovering = hovering }
        }
        .help("Connect \(device.name)")
    }
}
