import AppKit
import SwiftUI

/// Files parked in the notch: drag in to stash, drag out to use.
struct ShelfPanel: View {
    let model: NotchViewModel

    var body: some View {
        ZStack {
            if model.shelf.isEmpty {
                EmptyPanel(
                    symbol: "tray.and.arrow.down",
                    title: "Shelf is empty",
                    detail: "Drag files onto the notch to keep them here."
                )
            } else {
                contents
            }

            if model.isDropTargeted {
                dropTarget.transition(.opacity.combined(with: .scale(0.97)))
            }
        }
    }

    private var contents: some View {
        VStack(spacing: 6) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.shelf) { item in
                        ShelfTile(item: item, model: model)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.shelf.count == 1 ? "1 item" : "\(model.shelf.count) items")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))

            Spacer(minLength: 0)

            PillButton(title: "Share", symbol: "square.and.arrow.up") {
                guard let anchor = model.shareAnchor?() else { return }
                model.isInteractionLocked = true
                model.shelfStore?.share(model.shelf, relativeTo: anchor)
            }
            PillButton(title: "Clear", symbol: "trash") {
                model.shelfStore?.clear()
            }
        }
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                .white.opacity(0.45),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.clear)
                    .glassEffect(Glass.control, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .symbolEffect(.bounce, options: .repeating)
                    Text("Drop to add")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
    }
}

/// One file in the shelf. Draggable straight back out into any app.
private struct ShelfTile: View {
    let item: ShelfItem
    let model: NotchViewModel

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)

            Text(item.name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(.vertical, 7)
        .frame(width: 78)
        .glassEffect(
            Glass.control,
            in: .rect(cornerRadius: 12, style: .continuous)
        )
        .opacity(isHovering ? 1 : 0.82)
        .scaleEffect(isHovering ? 1.03 : 1)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    model.shelfStore?.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85), .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(Motion.pill) { isHovering = hovering }
        }
        .onDrag {
            // Hand the real file to whoever catches it.
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .onTapGesture(count: 2) {
            model.shelfStore?.open(item)
        }
        .contextMenu {
            Button("Open") { model.shelfStore?.open(item) }
            Button("Reveal in Finder") { model.shelfStore?.reveal(item) }
            Divider()
            Button("Remove") { model.shelfStore?.remove(item) }
        }
        .help(item.url.path)
    }
}

/// Small capsule action used in panel headers.
struct PillButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isHovering ? 1 : 0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .glassEffect(Glass.control, in: .capsule)
            .scaleEffect(isHovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.pill) { isHovering = hovering }
        }
    }
}
