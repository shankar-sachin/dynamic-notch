import SwiftUI

/// The four sizes the notch can be. Strictly ordered — bigger is later.
enum NotchMode: Int, Comparable, Sendable {
    /// Exactly the hardware notch. Black on black: the app is invisible.
    case idle
    /// Grown sideways to carry ambient accessories (album art, a level bar).
    case ambient
    /// A micro-bump under the cursor while an open is being considered.
    case hinted
    /// The full panel.
    case expanded

    static func < (a: NotchMode, b: NotchMode) -> Bool { a.rawValue < b.rawValue }
}

enum NotchTab: String, CaseIterable, Identifiable, Sendable {
    case home, shelf, timer, devices, tools

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "waveform"
        case .shelf: "tray.full"
        case .timer: "timer"
        case .devices: "dot.radiowaves.left.and.right"
        case .tools: "switch.2"
        }
    }
    var title: String {
        switch self {
        case .home: "Now Playing"
        case .shelf: "Shelf"
        case .timer: "Timer & Stopwatch"
        case .devices: "Devices"
        case .tools: "Quick Actions"
        }
    }
}

/// Hard numbers for the silhouette, in points.
enum NotchLayout {
    /// Body size of the open panel (excluding the corner flares).
    static let expandedSize = CGSize(width: 580, height: 178)

    /// Extra body width per side when ambient content is showing.
    static let accessoryWidth: CGFloat = 38
    /// How much the pill bumps when the cursor arrives but has not committed.
    static let hintGrowth = CGSize(width: 26, height: 6)

    /// Corner radii per mode: `top` is the concave flare where the shape peels
    /// away from the screen edge, `bottom` is the ordinary rounded underside.
    ///
    /// No flare, at any size.
    ///
    /// The concave top corner is the conventional trick for blending a notch
    /// panel into the bezel, and it was tried at both scales here: at pill size
    /// it reads as two black wings, and at panel size as a lump on the shoulder.
    /// Straight sides and a clean rounded underside look like the hardware.
    /// The shape still takes a top radius, so it's one number away if a future
    /// size ever earns it.
    static func radii(for mode: NotchMode) -> (top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .idle: (0, 10)        // exactly the hardware, so we vanish into it
        case .ambient: (0, 14)
        case .hinted: (0, 16)
        case .expanded: (0, 28)
        }
    }

    /// The pill keeps the hardware's own height. Hanging it lower reads as a
    /// bar bolted under the notch rather than the notch itself widening — the
    /// swoop belongs in the corner radius, not in extra height.
    static let ambientDrop: CGFloat = 0

    /// Slack around the panel so shadows and overshoot are never clipped.
    static let windowPadding = CGSize(width: 64, height: 72)

    static func windowSize(notch: CGSize) -> CGSize {
        let top = radii(for: .expanded).top
        return CGSize(
            width: max(expandedSize.width, notch.width) + top * 2 + windowPadding.width,
            height: expandedSize.height + windowPadding.height
        )
    }
}

/// The resolved geometry for one frame of the morph.
struct NotchPresentation: Equatable {
    var bodySize: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Outer width including both concave flares.
    var outerWidth: CGFloat { bodySize.width + topRadius * 2 }

    /// `maxSpread` caps how far each ear may extend past the notch, so the
    /// closed pill doesn't sit on top of the menu bar.
    static func resolve(
        mode: NotchMode,
        notch: CGSize,
        accessories: Int,
        maxSpread: CGFloat? = nil
    ) -> NotchPresentation {
        let radii = NotchLayout.radii(for: mode)
        let body: CGSize

        func spread(_ requested: CGFloat) -> CGFloat {
            guard let maxSpread else { return requested }
            return min(requested, maxSpread)
        }

        switch mode {
        case .idle:
            body = notch
        case .ambient:
            let ears = NotchLayout.accessoryWidth * CGFloat(max(accessories, 1)) / 2
            body = CGSize(
                width: notch.width + spread(ears) * 2,
                height: notch.height + NotchLayout.ambientDrop
            )
        case .hinted:
            let ears = (NotchLayout.accessoryWidth * CGFloat(accessories)
                + NotchLayout.hintGrowth.width) / 2
            body = CGSize(
                width: notch.width + spread(ears) * 2,
                height: notch.height + NotchLayout.ambientDrop + NotchLayout.hintGrowth.height
            )
        case .expanded:
            body = CGSize(
                width: max(NotchLayout.expandedSize.width, notch.width),
                height: NotchLayout.expandedSize.height
            )
        }

        return NotchPresentation(bodySize: body, topRadius: radii.top, bottomRadius: radii.bottom)
    }
}
