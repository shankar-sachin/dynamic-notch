import AppKit

/// Everything we need to know about the physical notch on a given display.
///
/// On a notched MacBook the metrics come straight from the window server via
/// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` — the two menu bar strips that
/// flank the camera housing. Whatever is left between them *is* the notch.
/// On every other display we synthesise a notch of pleasant proportions so the
/// app still has somewhere to live.
struct NotchMetrics: Equatable, Sendable {
    /// Full screen bounds in AppKit (bottom-left origin) global coordinates.
    var screenFrame: CGRect
    /// Size of the notch itself, in points.
    var notchSize: CGSize
    /// Horizontal centre of the notch in global coordinates.
    var notchCenterX: CGFloat
    /// False when we invented the notch for a display that has none.
    var isPhysical: Bool

    static let fallbackNotchSize = CGSize(width: 190, height: 32)

    /// Global rect the notch occupies, hanging from the top edge of the screen.
    var notchRect: CGRect {
        CGRect(
            x: notchCenterX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    static func measure(_ screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            if width > 1, height > 1 {
                return NotchMetrics(
                    screenFrame: frame,
                    notchSize: CGSize(width: width, height: height),
                    notchCenterX: frame.minX + left.width + width / 2,
                    isPhysical: true
                )
            }
        }

        return NotchMetrics(
            screenFrame: frame,
            notchSize: fallbackNotchSize,
            notchCenterX: frame.midX,
            isPhysical: false
        )
    }
}

extension NSScreen {
    /// The display the notch should live on: the built-in one if it is connected,
    /// otherwise whichever screen owns the menu bar.
    static var notchHost: NSScreen? {
        screens.first { $0.auxiliaryTopLeftArea != nil } ?? screens.first ?? main
    }
}
