import SwiftUI

/// The open panel.
///
/// Note what happens along the top edge: the camera housing is a *hole in the
/// display*, so nothing may be drawn in the notch's own column. The panel keeps
/// that band clear and uses the two ears beside it for a badge and the tab
/// switcher — the constraint becomes the layout.
struct ExpandedPanel: View {
    let model: NotchViewModel
    let timers: TimerService
    let stopwatch: StopwatchService
    let bluetooth: BluetoothService
    let actions: QuickActionsService
    var glue: Namespace.ID

    private var notch: CGSize { model.metrics.notchSize }

    var body: some View {
        if let device = model.deviceSpotlight {
            VStack(spacing: 0) {
                topBand
                DeviceSpotlight(device: device) {
                    model.endSpotlight()
                    model.select(.devices)
                    model.expand()
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
            .transition(.opacity.combined(with: .blurReplace))
        } else {
            tabbedPanel
        }
    }

    private var tabbedPanel: some View {
        VStack(spacing: 0) {
            topBand
            Group {
                switch model.selectedTab {
                case .home:
                    NowPlayingPanel(model: model, glue: glue)
                case .shelf:
                    ShelfPanel(model: model)
                case .timer:
                    TimePanel(
                        model: model,
                        timers: timers,
                        stopwatch: stopwatch,
                        clock: timers.clock
                    )
                case .devices:
                    DevicesPanel(model: model, bluetooth: bluetooth)
                case .tools:
                    ToolsPanel(model: model, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var topBand: some View {
        HStack(spacing: 0) {
            badge
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notch.width)
            if model.deviceSpotlight == nil {
                TabRail(model: model)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .frame(height: notch.height)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var badge: some View {
        if let device = model.deviceSpotlight {
            HStack(spacing: 6) {
                Image(systemName: device.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Bluetooth")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
        } else {
            mediaBadge
        }
    }

    @ViewBuilder
    private var mediaBadge: some View {
        let source = model.nowPlaying?.source
        HStack(spacing: 6) {
            Image(systemName: source?.symbol ?? "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(source?.tint ?? .white.opacity(0.7))
            Text(source?.displayName ?? "Dynamic Notch")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .contentTransition(.opacity)
    }
}

/// Tab switcher living in the notch's right ear.
struct TabRail: View {
    let model: NotchViewModel
    @Namespace private var indicator

    var body: some View {
        // A container lets the chips flow into one another as the selection
        // moves, instead of each one blurring its own patch of background.
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(NotchTab.allCases) { tab in
                    let selected = model.selectedTab == tab
                    Button {
                        model.select(tab)
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(selected ? .white : .white.opacity(0.45))
                            .frame(width: 27, height: 21)
                            .glassEffect(
                                selected ? Glass.control : .identity,
                                in: .capsule
                            )
                            .glassEffectID(tab.rawValue, in: indicator)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
        }
        .animation(Motion.content, value: model.selectedTab)
    }
}
