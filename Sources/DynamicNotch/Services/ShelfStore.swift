import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One file parked in the notch's shelf.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var name: String
    var icon: NSImage
    /// True when we wrote the file ourselves (dropped text or an image, rather
    /// than a file that already lived somewhere) and may delete it on removal.
    var isStaged: Bool

    static func == (a: ShelfItem, b: ShelfItem) -> Bool { a.id == b.id }
}

/// Keeps the shelf's contents.
///
/// Dropped *files* are held by reference — nothing is copied, so the shelf is a
/// pointer to your file, not a duplicate of it. Dropped *content* (an image
/// dragged out of a browser, a snippet of text) has no file yet, so it gets
/// written into Application Support and cleaned up when removed.
///
/// The shelf survives quitting. Only paths are saved, never icons or contents,
/// and anything that has since been moved, renamed or deleted is dropped on the
/// way back in — a shelf full of entries that no longer open would be worse
/// than an empty one.
@MainActor
final class ShelfStore {
    private let model: NotchViewModel

    private lazy var stagingDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("DynamicNotch/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    init(model: NotchViewModel) {
        self.model = model
    }

    // MARK: Persistence

    private var ledger: URL { stagingDirectory.appendingPathComponent("shelf.json") }

    private struct Entry: Codable {
        var path: String
        var name: String
        var isStaged: Bool
    }

    /// Called at launch.
    func restore() {
        guard let data = try? Data(contentsOf: ledger),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }

        let manager = FileManager.default
        var recovered: [ShelfItem] = []
        var lost = 0

        for entry in entries {
            guard manager.fileExists(atPath: entry.path) else {
                lost += 1
                continue
            }
            let url = URL(fileURLWithPath: entry.path)
            recovered.append(
                ShelfItem(
                    url: url,
                    // Follow a rename rather than showing the old name.
                    name: url.lastPathComponent,
                    icon: NSWorkspace.shared.icon(forFile: entry.path),
                    isStaged: entry.isStaged
                )
            )
        }

        model.shelf = recovered
        if lost > 0 { save() }
        Log.app.info("shelf restored \(recovered.count) item(s), dropped \(lost) missing")
    }

    private func save() {
        let entries = model.shelf.map {
            Entry(path: $0.url.path, name: $0.name, isStaged: $0.isStaged)
        }
        do {
            try JSONEncoder().encode(entries).write(to: ledger, options: .atomic)
        } catch {
            Log.app.error("shelf save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Dropping

    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .png, .tiff, .rtf, .string,
    ]

    func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self, NSImage.self, NSString.self])
    }

    @discardableResult
    func accept(_ pasteboard: NSPasteboard) -> Int {
        var added: [ShelfItem] = []

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            added += urls.map(item(referencing:))
        }

        if added.isEmpty, let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] {
            added += images.compactMap(stage(image:))
        }

        if added.isEmpty, let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String] {
            added += strings.compactMap(stage(text:))
        }

        guard !added.isEmpty else { return 0 }

        // Newest first, and never the same file twice.
        withAnimation(Motion.content) {
            for entry in added.reversed() {
                model.shelf.removeAll { $0.url == entry.url }
                model.shelf.insert(entry, at: 0)
            }
        }

        save()
        model.present(.event(EventActivity(
            symbol: "tray.and.arrow.down.fill",
            tint: .white,
            title: added.count == 1 ? "Added to Shelf" : "\(added.count) items added",
            detail: added.count == 1 ? added[0].name : nil
        )))

        Log.app.info("shelf accepted \(added.count) item(s)")
        return added.count
    }

    private func item(referencing url: URL) -> ShelfItem {
        ShelfItem(
            url: url,
            name: url.lastPathComponent,
            icon: NSWorkspace.shared.icon(forFile: url.path),
            isStaged: false
        )
    }

    private func stage(image: NSImage) -> ShelfItem? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let url = stagingDirectory.appendingPathComponent("Image \(Self.stamp()).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return ShelfItem(url: url, name: url.lastPathComponent, icon: image, isStaged: true)
    }

    private func stage(text: String) -> ShelfItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url = stagingDirectory.appendingPathComponent("Note \(Self.stamp()).txt")
        guard (try? trimmed.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return ShelfItem(
            url: url,
            name: url.lastPathComponent,
            icon: NSWorkspace.shared.icon(for: .plainText),
            isStaged: true
        )
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: .now)
    }

    // MARK: Managing

    func remove(_ item: ShelfItem) {
        withAnimation(Motion.content) {
            model.shelf.removeAll { $0.id == item.id }
        }
        if item.isStaged {
            try? FileManager.default.removeItem(at: item.url)
        }
        save()
    }

    func clear() {
        let staged = model.shelf.filter(\.isStaged)
        withAnimation(Motion.content) { model.shelf.removeAll() }
        for item in staged {
            try? FileManager.default.removeItem(at: item.url)
        }
        save()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    /// The standard share sheet — which is where AirDrop lives.
    func share(_ items: [ShelfItem], relativeTo view: NSView) {
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items.map(\.url))
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
