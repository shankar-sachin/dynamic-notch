import SwiftUI

/// Round glyph button with a hover halo and a press squish.
struct NotchButton<Label: View>: View {
    var size: CGFloat = 32
    var filled: Bool = false
    var tint: Color = .white
    var action: () -> Void
    @ViewBuilder var label: Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(Style(size: size, filled: filled, isHovering: isHovering, tint: tint))
            .onHover { hovering in
                withAnimation(Motion.pill) { isHovering = hovering }
            }
    }

    private struct Style: ButtonStyle {
        var size: CGFloat
        var filled: Bool
        var isHovering: Bool
        var tint: Color

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.white.opacity(filled || isHovering ? 1 : 0.8))
                .frame(width: size, height: size)
                // Only the primary control wears chrome at rest. Glass on the
                // secondaries put a ringed disc around each one, which against
                // pure black reads as a smudge rather than a button — so they
                // are bare glyphs until the pointer arrives, and the ring is
                // the hover affordance rather than permanent decoration.
                .glassEffect(glass(isHovering: isHovering), in: .circle)
                .scaleEffect(configuration.isPressed ? 0.88 : (isHovering ? 1.06 : 1))
                .animation(Motion.pill, value: configuration.isPressed)
                .animation(Motion.pill, value: isHovering)
                .contentShape(Circle())
        }

        private func glass(isHovering: Bool) -> SwiftUI.Glass {
            if filled { return Glass.accent(tint) }
            return isHovering ? Glass.control : .identity
        }
    }
}

/// Draggable playhead. Scrubbing holds the panel open so it can't fold up
/// mid-gesture.
struct Scrubber: View {
    var progress: Double
    var elapsed: TimeInterval
    var remaining: TimeInterval
    var tint: Color
    var onScrub: (Double) -> Void
    var onScrubStateChange: (Bool) -> Void

    @State private var isDragging = false
    @State private var draft: Double = 0

    private var shown: Double { isDragging ? draft : progress }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.75), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(1, shown)) * width)
                        .shadow(color: tint.opacity(0.55), radius: isDragging ? 7 : 4)
                        .overlay(alignment: .trailing) {
                            // A bead of light at the playhead, which swells
                            // under your finger.
                            Circle()
                                .fill(.white)
                                .frame(width: isDragging ? 9 : 0, height: isDragging ? 9 : 0)
                                .shadow(color: tint, radius: 6)
                                .offset(x: 4)
                        }
                }
                .frame(height: isDragging ? 6 : 4)
                .frame(height: 12, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onScrubStateChange(true)
                            }
                            draft = min(max(0, value.location.x / max(width, 1)), 1)
                        }
                        .onEnded { _ in
                            isDragging = false
                            onScrubStateChange(false)
                            onScrub(draft)
                        }
                )
                .animation(Motion.pill, value: isDragging)
            }
            .frame(height: 12)

            HStack {
                Text(Self.clock(elapsed))
                Spacer(minLength: 0)
                Text("-" + Self.clock(remaining))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
