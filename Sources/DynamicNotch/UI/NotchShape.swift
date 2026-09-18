import SwiftUI

/// The notch silhouette: square at the top where it meets the bezel, rounded
/// underneath, and — the detail that makes or breaks it — *concave* at the two
/// top corners, so the black doesn't sit on the screen edge, it grows out of it.
///
/// The path's `rect` is the **outer** box. The flat body between the two flares
/// is `rect.width - 2 * topRadius`, which is why `NotchPresentation.outerWidth`
/// pads the body by the radius on each side.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Radii have to survive mid-animation sizes, including a body that is
        // briefly narrower than the corners want to be.
        let top = max(0, min(topRadius, rect.width / 2, rect.height))
        let bodyWidth = rect.width - top * 2
        let bottom = max(0, min(bottomRadius, bodyWidth / 2, rect.height - top))

        let leftWall = rect.minX + top
        let rightWall = rect.maxX - top
        let shoulder = rect.minY + top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left: peel away from the screen edge. With no flare the corner is
        // a plain right angle — said explicitly rather than left to a zero-radius
        // arc between two coincident points.
        if top > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: shoulder),
                tangent2End: CGPoint(x: leftWall, y: shoulder),
                radius: top
            )
        }
        // Down the left wall and around the underside.
        path.addArc(
            tangent1End: CGPoint(x: leftWall, y: rect.maxY),
            tangent2End: CGPoint(x: rightWall, y: rect.maxY),
            radius: bottom
        )
        path.addArc(
            tangent1End: CGPoint(x: rightWall, y: rect.maxY),
            tangent2End: CGPoint(x: rightWall, y: shoulder),
            radius: bottom
        )
        // Top-right: back into the screen edge.
        if top > 0 {
            path.addArc(
                tangent1End: CGPoint(x: rightWall, y: shoulder),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
                radius: top
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

extension NotchShape {
    init(_ presentation: NotchPresentation) {
        self.init(topRadius: presentation.topRadius, bottomRadius: presentation.bottomRadius)
    }
}
