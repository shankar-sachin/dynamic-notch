import SwiftUI

/// The AirPods showcase: the open case turns into view with the buds sitting
/// inside it, turns slowly on the spot, and then the buds lift out of the box.
///
/// The case is built as separate layers — back wall, buds, front wall — rather
/// than one picture. That's what makes the buds genuinely *inside* it: they're
/// drawn between the two walls, so the front wall hides their lower halves, and
/// as they lift they emerge from behind its rim. An occlusion, not a crossfade.
///
/// There is no lid. A hinged one was built and rotated properly on its back
/// edge, but a flat panel swung past 90° reads as a bar floating over the case,
/// not as a lid — the illusion needs a thickness these layers don't have. The
/// case simply arrives open instead, which is the state worth showing anyway.
///
/// The turn is a slow sway rather than a full revolution. These are flat layers,
/// and a flat case rotated past 90° would collapse to nothing and come back
/// mirrored, with the lid hinged on the wrong side. A gentle turntable reads as
/// a 3D object on show; a full spin would give the trick away.
struct AirPodsStage: View {
    var kind: BluetoothDevice.Kind
    var beat: Beat

    enum Beat: Int, Comparable {
        case offstage, arrived, lidOpen, emerged, separated
        static func < (a: Beat, b: Beat) -> Bool { a.rawValue < b.rawValue }
    }

    @State private var sway = false
    @State private var bob = false

    private var hasCase: Bool { kind == .airpods || kind == .airpodsPro }
    private var isOpen: Bool { beat >= .lidOpen }
    private var isOut: Bool { beat >= .emerged }

    // Geometry, all relative to the centre of the stage.
    private let caseWidth: CGFloat = 60
    private let bodyHeight: CGFloat = 46
    private let bodyCentre: CGFloat = 12

    var body: some View {
        if hasCase {
            assembly
                .frame(width: 140, height: 112)
                .onAppear {
                    withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                        sway = true
                    }
                    withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                        bob = true
                    }
                }
        } else {
            // Over-ear and anything else: no case to open, so it just arrives.
            Image(systemName: kind.symbol)
                .font(.system(size: 50, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .scaleEffect(beat >= .arrived ? 1 : 0.6)
                .opacity(beat >= .arrived ? 1 : 0)
                .frame(width: 140, height: 112)
        }
    }

    private var assembly: some View {
        ZStack {
            backWall.zIndex(1)
            buds.zIndex(2)
            frontWall.zIndex(3)
        }
        // The slow turn on the spot, and a breath of float under it.
        .rotation3DEffect(
            .degrees(beat >= .arrived ? (sway ? 17 : -17) : -34),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: 0.42
        )
        .offset(y: bob ? -3 : 3)
        .scaleEffect(beat >= .arrived ? 1 : 0.6)
        .opacity(beat >= .arrived ? 1 : 0)
        .shadow(color: .black.opacity(0.5), radius: 12, y: 7)
    }

    // MARK: The box

    /// The inside of the case: darker, so the buds read as sitting down in it.
    private var backWall: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.30), Color(white: 0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: caseWidth, height: bodyHeight)
            .offset(y: bodyCentre)
    }

    /// The front of the case, which the buds rise out from behind.
    private var frontWall: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(shell)
            .frame(width: caseWidth, height: 30)
            .overlay(alignment: .top) {
                // The rim catches the light.
                Rectangle()
                    .fill(.white.opacity(0.55))
                    .frame(height: 0.75)
            }
            .overlay(alignment: .bottom) {
                // Pairing light, on once the lid is up.
                Circle()
                    .fill(isOpen ? Color.green : Color(white: 0.55))
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: .green.opacity(isOpen ? 0.9 : 0), radius: 5)
                    .padding(.bottom, 8)
            }
            .offset(y: bodyCentre + (bodyHeight - 30) / 2)
    }

    private var shell: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.98), Color(white: 0.87), Color(white: 0.76)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: The buds

    /// Nested in the case until they're taken out.
    ///
    /// SF Symbols has no single AirPod — only the pair — so the pair is drawn
    /// twice, each copy masked to one half. Apple's artwork, genuinely halved.
    private var buds: some View {
        ZStack {
            bud(.leading)
            bud(.trailing)
        }
        .offset(y: isOut ? -32 : 4)
        .scaleEffect(isOut ? 1 : 0.9)
    }

    private func bud(_ side: Alignment) -> some View {
        let isLeft = side == .leading
        return Image(systemName: kind == .airpodsPro ? "airpodspro" : "airpods")
            .font(.system(size: 44, weight: .regular))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(white: 1.0), Color(white: 0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask(alignment: side) {
                GeometryReader { geometry in
                    Rectangle()
                        .frame(width: geometry.size.width / 2)
                        .frame(maxWidth: .infinity, alignment: side)
                }
            }
            // Sitting in the case they're close together; out of it they part.
            .offset(x: beat >= .separated ? (isLeft ? -14 : 14) : (isLeft ? -1 : 1))
            .rotationEffect(.degrees(beat >= .separated ? (isLeft ? -8 : 8) : 0))
            .shadow(color: .black.opacity(isOut ? 0.5 : 0), radius: 6, y: 3)
    }
}
