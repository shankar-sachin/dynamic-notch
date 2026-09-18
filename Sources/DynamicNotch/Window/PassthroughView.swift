import AppKit

/// What the content view needs from whoever owns the drag.
@MainActor
protocol NotchDropHandling: AnyObject {
    func notchDragEntered(_ pasteboard: NSPasteboard) -> Bool
    func notchDragExited()
    func notchPerformDrop(_ pasteboard: NSPasteboard) -> Bool
}

/// The panel's content view.
///
/// The window is permanently the size of the *fully open* panel — that's the
/// trick that keeps the morph fluid, since nothing ever resizes mid-animation.
/// The cost is a big invisible rectangle sitting over the top of the screen, so
/// this view hands every event outside the drawn silhouette back to whatever is
/// underneath. The menu bar stays clickable; the notch only eats what it draws.
final class PassthroughView: NSView {
    /// Current interactive area, in this view's coordinates.
    var interactiveRect: () -> CGRect = { .zero }
    /// Extra forgiveness around that area for clicks (not for drawing).
    var touchSlop: CGFloat = 4

    weak var dropHandler: (any NotchDropHandling)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ShelfStore.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect().insetBy(dx: -touchSlop, dy: -touchSlop).contains(local) else {
            return nil
        }
        return super.hitTest(point)
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    /// Act on the first click even though the app isn't frontmost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Dragging destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler?.notchDragEntered(sender.draggingPasteboard) == true ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler?.notchDragEntered(sender.draggingPasteboard) == true ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropHandler?.notchDragExited()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropHandler?.notchDragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropHandler?.notchPerformDrop(sender.draggingPasteboard) ?? false
    }
}
