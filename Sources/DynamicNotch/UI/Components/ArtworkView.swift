import AppKit
import SwiftUI

/// Album art, or a tasteful stand-in when there is none.
struct ArtworkView: View {
    var image: NSImage?
    var accent: Color = .gray
    var cornerRadius: CGFloat = 6
    var symbol: String = "music.note"

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.85), accent.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: cornerRadius * 1.6, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            // A hairline keeps dark art from dissolving into the black body.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}
