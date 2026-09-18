import SwiftUI

/// Text that scrolls only when it has to.
///
/// The offset is derived from the timeline clock rather than from a repeating
/// animation, so it can never desync, double up, or keep running after the view
/// is reused for a different track. Each cycle holds still for a beat at the
/// start, which is what makes it read as *considered* instead of restless.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 13, weight: .semibold)
    var color: Color = .white
    /// Points per second.
    var speed: Double = 26
    /// Beat of stillness before each pass.
    var hold: Double = 1.7
    /// Space between the tail and the repeat.
    var gap: CGFloat = 44

    @State private var textWidth: CGFloat = 0
    @State private var viewWidth: CGFloat = 0

    private var overflows: Bool { textWidth > viewWidth + 0.5 }

    var body: some View {
        ZStack(alignment: .leading) {
            if overflows {
                TimelineView(.animation) { context in
                    label
                        .offset(x: offset(at: context.date))
                        .overlay(alignment: .leading) {
                            label.offset(x: offset(at: context.date) + textWidth + gap)
                        }
                }
            } else {
                label
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewWidth = $0 }
        .background(alignment: .leading) {
            // An unclipped copy, purely to measure the natural width.
            label
                .hidden()
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
        }
        .clipped()
        .mask(alignment: .leading) { fade }
        .animation(nil, value: text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    /// Soft edges so text dissolves rather than being guillotined.
    private var fade: some View {
        LinearGradient(
            stops: overflows
                ? [.init(color: .black, location: 0),
                   .init(color: .black, location: 0.88),
                   .init(color: .clear, location: 1)]
                : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func offset(at date: Date) -> CGFloat {
        let travel = textWidth + gap
        guard travel > 0 else { return 0 }
        let duration = travel / speed + hold
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return t < hold ? 0 : -CGFloat((t - hold) * speed)
    }
}
