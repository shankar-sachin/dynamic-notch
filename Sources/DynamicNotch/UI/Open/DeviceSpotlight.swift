import SwiftUI

/// The card a phone throws up when the case opens: the AirPods, large and
/// moving, with what's left in each piece.
///
/// It takes over the whole panel rather than sharing with the tabs, because
/// that's the point — it interrupts, says one thing, and leaves.
///
/// The sequence is deliberately unhurried and strictly ordered: the case turns
/// into view, the lid swings open, the buds rise out and part, and only then do
/// the meters fill. Every beat is caused by the one before it, which is what
/// makes Apple's own transitions read as physical rather than decorative.
struct DeviceSpotlight: View {
    let device: BluetoothDevice
    var onOpenDevices: () -> Void

    @State private var beat: AirPodsStage.Beat = .offstage
    @State private var textIn = false
    @State private var charged = false

    var body: some View {
        HStack(spacing: 18) {
            AirPodsStage(kind: device.kind, beat: beat)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Connected")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                if device.hasAnyBattery {
                    HStack(spacing: 14) {
                        if device.kind.hasEarpieces {
                            meter("Left", device.batteryLeft)
                            meter("Right", device.batteryRight)
                            meter("Case", device.batteryCase, symbol: "case.fill")
                        } else {
                            meter(nil, device.batterySingle ?? device.headlineBattery)
                        }
                    }
                } else {
                    // Charge isn't reported the instant it connects.
                    Text("Checking battery…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .offset(y: textIn ? 0 : 10)
            .opacity(textIn ? 1 : 0)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDevices)
        .task(id: device.address) { await play() }
    }

    /// The timeline. Each beat gets the curve that suits the movement: the lid
    /// is light and swings with some bounce, the buds have a little mass.
    ///
    /// The case is given a proper pause once it's open — that's the beat where
    /// it's just sitting there turning, which is the shot worth holding — before
    /// the buds are lifted out.
    private func play() async {
        beat = .offstage
        textIn = false
        charged = false

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { beat = .arrived }

        try? await Task.sleep(for: .milliseconds(340))
        withAnimation(.spring(response: 0.44, dampingFraction: 0.55)) { beat = .lidOpen }
        withAnimation(.easeOut(duration: 0.4)) { textIn = true }

        // Hold: lid open, buds visible inside, case turning.
        try? await Task.sleep(for: .milliseconds(1250))
        withAnimation(.spring(response: 0.58, dampingFraction: 0.64)) { beat = .emerged }

        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { beat = .separated }

        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { charged = true }
    }

    @ViewBuilder
    private func meter(_ label: String?, _ level: Int?, symbol: String? = nil) -> some View {
        if let level {
            VStack(spacing: 4) {
                ZStack {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: charged ? Double(level) / 100 : 0)
                        .stroke(tint(level), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint(level).opacity(0.5), radius: 4)

                    Text("\(level)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .frame(width: 38, height: 38)

                HStack(spacing: 3) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 7, weight: .bold))
                    }
                    if let label {
                        Text(label).font(.system(size: 9, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func tint(_ level: Int) -> Color {
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }
}
