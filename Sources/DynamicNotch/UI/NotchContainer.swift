import SwiftUI

struct NotchRootView: View {
    let model: NotchViewModel
    let timers: TimerService
    let stopwatch: StopwatchService
    let bluetooth: BluetoothService
    let actions: QuickActionsService

    var body: some View {
        NotchContainer(
            model: model,
            timers: timers,
            stopwatch: stopwatch,
            bluetooth: bluetooth,
            actions: actions
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.all)
    }
}

/// The body of the notch: one black shape that changes size, with content
/// swapped inside it.
///
/// Nothing here resizes a window. The panel is always the size of the fully
/// open panel; this view animates a shape within it. That's the whole reason
/// the morph can be continuous instead of stepping a frame at a time.
struct NotchContainer: View {
    let model: NotchViewModel
    let timers: TimerService
    let stopwatch: StopwatchService
    let bluetooth: BluetoothService
    let actions: QuickActionsService
    @Namespace private var glue

    /// How much "inside light" to show: none when the notch is pretending to be
    /// hardware, full when it's a panel.
    private var lightLevel: Double {
        switch model.mode {
        case .idle: 0
        case .ambient: 0.25
        case .hinted: 0.5
        case .expanded: 1
        }
    }

    var body: some View {
        let presentation = model.presentation
        let shape = NotchShape(presentation)

        content
            .frame(width: presentation.bodySize.width, height: presentation.bodySize.height, alignment: .top)
            .padding(.horizontal, presentation.topRadius)
            .background {
                // Black, and only black. The body has to be the same dead black
                // as the camera housing at every size, or the moment it grows
                // past the hardware you can see exactly where the notch ends.
                // Colour lives on the *contents* — the artwork's glow, the
                // scrubber, a tinted control — never on the body.
                shape.fill(.black)
            }
            .overlay {
                // A hairline of light on the underside, the way a real bezel
                // edge catches it. Barely there by design.
                shape
                    .stroke(Glass.rim, lineWidth: 0.75)
                    .opacity(lightLevel * 0.7)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.55 * lightLevel), radius: 26, y: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(shape)
            .onTapGesture {
                // Click the pill to open; clicking inside the open panel is for
                // the controls, not for dismissing it.
                if !model.isExpanded { model.expand() }
            }
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            if model.isExpanded {
                ExpandedPanel(
                    model: model,
                    timers: timers,
                    stopwatch: stopwatch,
                    bluetooth: bluetooth,
                    actions: actions,
                    glue: glue
                )
                    .transition(
                        .opacity
                            .combined(with: .scale(0.94, anchor: .top))
                            .combined(with: .blurReplace)
                    )
            } else {
                ClosedPill(model: model, glue: glue)
                    .transition(.opacity.combined(with: .blurReplace))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
