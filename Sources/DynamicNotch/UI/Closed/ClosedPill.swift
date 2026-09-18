import SwiftUI

/// The notch at rest.
///
/// The middle of the pill is a hole — that's where the camera actually is, so
/// nothing may be drawn there. Everything lives in the two ears either side,
/// which is exactly the constraint that gives the island its look, and the
/// reason a timer can run on the right while album art sits on the left.
struct ClosedPill: View {
    let model: NotchViewModel
    var glue: Namespace.ID

    private var notchWidth: CGFloat { model.metrics.notchSize.width }
    private var notchHeight: CGFloat { model.metrics.notchSize.height }
    /// The pill hangs a little below the notch line, and the ears centre in the
    /// whole of it — which is what puts the artwork in the swoop rather than
    /// leaving it stranded up in the hardware's own band.
    private var bodyHeight: CGFloat { model.presentation.bodySize.height }
    /// Artwork and glyphs scale with the hardware, so this looks right on any Mac.
    private var glyphSize: CGFloat { max(16, bodyHeight - 14) }

    var body: some View {
        let plan = model.pill

        HStack(spacing: 0) {
            slot(plan.leading, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 11)
            Color.clear.frame(width: notchWidth)
            slot(plan.trailing, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 11)
        }
        .frame(height: bodyHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.content, value: plan)
    }

    @ViewBuilder
    private func slot(_ slot: PillSlot, alignment: HorizontalAlignment) -> some View {
        switch slot {
        case .empty:
            EmptyView()

        case .artwork(let track):
            ArtworkView(image: track.artwork, accent: track.accent, cornerRadius: 5)
                .matchedGeometryEffect(id: "artwork", in: glue, isSource: !model.isExpanded)
                .frame(width: glyphSize, height: glyphSize)
                .shadow(color: track.accent.opacity(0.5), radius: 5)

        case .bars(let track):
            AudioBars(
                isActive: track.isPlaying,
                tint: track.accent,
                maxHeight: min(15, bodyHeight - 16)
            )

        case .levelIcon(let level):
            Image(systemName: level.kind.symbol(value: level.value, muted: level.isMuted))
                .font(.system(size: glyphSize * 0.58, weight: .medium))
                .foregroundStyle(level.kind.tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: glyphSize)

        case .levelBar(let level):
            LevelBar(value: level.isMuted ? 0 : level.value, tint: level.kind.tint)
                .frame(height: 4)
                .padding(.leading, 4)

        case .eventIcon(let event):
            Image(systemName: event.symbol)
                .font(.system(size: glyphSize * 0.62, weight: .semibold))
                .foregroundStyle(event.tint)
                .transition(.scale.combined(with: .opacity))

        case .eventDetail(let event):
            HStack(spacing: 7) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    if let detail = event.detail {
                        Text(detail)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)

                if let meter = event.meter {
                    BatteryGlyph(level: meter, tint: event.tint)
                        .frame(width: 22, height: 11)
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))

        case .timerGlyph(let timer):
            Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                .font(.system(size: glyphSize * 0.58, weight: .semibold))
                .foregroundStyle(.orange)
                .contentTransition(.symbolEffect(.replace))

        case .timerCountdown(let timer):
            TimerPip(timer: timer, height: min(17, bodyHeight - 14))

        case .stopwatchGlyph:
            Image(systemName: "stopwatch.fill")
                .font(.system(size: glyphSize * 0.58, weight: .semibold))
                .foregroundStyle(.cyan)

        case .stopwatchElapsed(let watch):
            // Coarse in the pill: centiseconds here would be a flicker, not
            // information. The panel has the precise readout.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(StopwatchState.coarse(watch.elapsed(at: context.date)))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }

        case .dropIcon:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: glyphSize * 0.62, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeating)

        case .dropLabel:
            Text("Drop")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: glyphSize * 0.52, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .transition(.scale.combined(with: .opacity))

        case .privacy(let privacy):
            Image(systemName: privacy.symbol)
                .font(.system(size: glyphSize * 0.5, weight: .semibold))
                .foregroundStyle(privacy.tint)
                .help(privacy.title)
        }
    }
}

/// The running countdown, as it appears in the closed pill: a ring that drains,
/// with the time beside it.
struct TimerPip: View {
    var timer: TimerState
    var height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = timer.remaining(at: context.date)
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: 1 - timer.progress(at: context.date))
                        .stroke(
                            timer.isPaused ? Color.white.opacity(0.5) : .orange,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: height, height: height)

                Text(TimerState.clock(remaining))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .opacity(timer.isPaused ? 0.6 : 1)
        }
    }
}

/// A slim capped meter — volume, brightness, battery.
struct LevelBar: View {
    var value: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geometry.size.width)
                    .shadow(color: tint.opacity(0.6), radius: 4)
            }
        }
        .animation(Motion.track, value: value)
    }
}

/// A tiny battery that actually fills to the level it's reporting.
struct BatteryGlyph: View {
    var level: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { geometry in
            let capWidth = geometry.size.width * 0.08
            let bodyWidth = geometry.size.width - capWidth - 1.5
            let inset: CGFloat = 1.5

            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint)
                        .padding(inset)
                        .frame(width: max(2, (bodyWidth - inset * 2) * min(max(level, 0), 1) + inset * 2))
                }
                .frame(width: bodyWidth)

                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: capWidth, height: geometry.size.height * 0.38)
            }
        }
        .animation(Motion.track, value: level)
    }
}
