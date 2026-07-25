import AppKit
import Foundation

enum Clipboard {
    /// Marker recognised by clipboard managers (and respected by several sync
    /// tools) meaning "do not record or sync this item". We are writing to the
    /// pasteboard very frequently; without this, history fills with noise and
    /// every selection would be eligible for Universal Clipboard sync.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static var currentString: String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Writes plain text. Returns false when the write was skipped.
    @discardableResult
    static func write(_ text: String, concealed: Bool) -> Bool {
        // Never clobber a good clipboard with nothing.
        guard !text.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        // Skip no-op writes so clipboard-manager history stays clean.
        guard text != currentString else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if concealed {
            pasteboard.setData(Data(), forType: concealedType)
        }
        return pasteboard.setString(text, forType: .string)
    }

    /// A full copy of the pasteboard, across all flavors, so the Cmd+C fallback
    /// can put things back if the copy did not produce usable text.
    ///
    /// Restoring is inherently lossy: promised file data and some custom flavors
    /// cannot be reproduced. That is one more reason the fallback path is gated
    /// as narrowly as possible.
    static func snapshot() -> (changeCount: Int, items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        let copies: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        return (pasteboard.changeCount, copies)
    }

    static func restore(_ snapshot: (changeCount: Int, items: [NSPasteboardItem])) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !snapshot.items.isEmpty {
            pasteboard.writeObjects(snapshot.items)
        }
    }
}
