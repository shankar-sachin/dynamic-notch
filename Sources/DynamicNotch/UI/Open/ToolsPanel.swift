import SwiftUI

/// Quick actions — the handful of things worth a flick to the top of the screen.
struct ToolsPanel: View {
    let model: NotchViewModel
    let actions: QuickActionsService

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 9) {
                tool(
                    symbol: actions.isDarkMode ? "sun.max.fill" : "moon.fill",
                    title: actions.isDarkMode ? "Light" : "Dark",
                    tint: .indigo,
                    action: actions.toggleDarkMode
                )
                tool(
                    symbol: actions.isKeepingAwake ? "cup.and.saucer.fill" : "zzz",
                    title: actions.isKeepingAwake ? "Awake" : "Caffeine",
                    tint: .brown,
                    isOn: actions.isKeepingAwake,
                    action: actions.toggleKeepAwake
                )
                tool(
                    symbol: "camera.viewfinder",
                    title: "Capture",
                    tint: .teal,
                    action: actions.screenshot
                )
                tool(
                    symbol: "lock.fill",
                    title: "Lock",
                    tint: .blue,
                    action: actions.lockScreen
                )
                tool(
                    symbol: "powersleep",
                    title: "Sleep",
                    tint: .purple,
                    action: actions.sleepNow
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tool(
        symbol: String,
        title: String,
        tint: Color,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? .white : tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isOn ? 0.95 : 0.6))
            }
            .frame(width: 74, height: 68)
            .glassEffect(isOn ? Glass.accent(tint) : Glass.control, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ToolButtonStyle())
        .help(title)
    }
}

private struct ToolButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : (isHovering ? 1.05 : 1))
            .animation(Motion.pill, value: configuration.isPressed)
            .animation(Motion.pill, value: isHovering)
            .onHover { isHovering = $0 }
    }
}
