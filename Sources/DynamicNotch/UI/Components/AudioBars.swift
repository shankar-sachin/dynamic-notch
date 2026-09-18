import SwiftUI

/// The little dancing bars in the trailing accessory.
///
/// Not a real FFT — macOS won't hand us another app's audio — but a set of
/// incommensurable sine waves reads as music to the eye, and it costs nothing.
/// It genuinely stops when playback stops, which is the part people notice.
struct AudioBars: View {
    var isActive: Bool
    var tint: Color = .white
    var barCount: Int = 4
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 14
    var minHeight: CGFloat = 3

    private let speeds: [Double] = [1.35, 2.05, 1.65, 2.45]
    private let phases: [Double] = [0, 1.9, 3.4, 0.8]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: barWidth, height: height(index, at: context.date))
                }
            }
            .frame(height: maxHeight)
            .animation(.linear(duration: 1.0 / 30.0), value: isActive)
        }
        .drawingGroup()
    }

    private func height(_ index: Int, at date: Date) -> CGFloat {
        guard isActive else { return minHeight }
        let t = date.timeIntervalSinceReferenceDate
        let i = index % speeds.count
        let wave = (sin(t * speeds[i] * .pi + phases[i]) + 1) / 2
        // A second, slower wave keeps any two bars from looking synchronised.
        let sway = (sin(t * 0.37 * .pi + Double(i)) + 1) / 2
        let level = wave * 0.78 + sway * 0.22
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }
}
