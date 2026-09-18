import SwiftUI

/// One line of text that truncates rather than growing.
///
/// The important part is what this *doesn't* do: it never calls `.fixedSize()`,
/// so it has no minimum width. A `Text` that sizes to its content gives every
/// stack above it a minimum equal to the whole string, and one long album title
/// then drags the panel wider than the notch — which is exactly the bug this
/// replaced. Here the container decides the width and the string gives way.
struct NotchText: View {
    let text: String
    var font: Font = .system(size: 13, weight: .semibold)
    var color: Color = .white
    /// `.tail` for titles; `.middle` reads better for filenames.
    var truncation: Text.TruncationMode = .tail

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(truncation)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
