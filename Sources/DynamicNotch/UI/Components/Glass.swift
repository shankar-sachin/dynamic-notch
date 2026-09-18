import SwiftUI

/// The material vocabulary, in one place — the counterpart to `Motion`.
///
/// The notch *body* is never glass. It has to be the same dead black as the
/// camera housing or the illusion breaks, and no amount of beautiful material
/// is worth a visible seam against the hardware. Everything that floats *inside*
/// the body is glass, lit as if the light were coming from above the lid.
enum Glass {
    /// Controls: transport buttons, tab chips, shelf actions.
    static let control = SwiftUI.Glass.regular.interactive()

    /// Tinted glass for the element that's currently doing something.
    static func accent(_ color: Color) -> SwiftUI.Glass {
        SwiftUI.Glass.regular.tint(color.opacity(0.55)).interactive()
    }

    /// Light along the bottom curve, where a real bezel edge would catch it.
    static let rim = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.07), location: 0),
            .init(color: .white.opacity(0.015), location: 0.5),
            .init(color: .white.opacity(0.13), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

}
