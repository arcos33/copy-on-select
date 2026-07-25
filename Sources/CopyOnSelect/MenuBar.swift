import AppKit
import Foundation

/// Minimal status-bar item: an off switch, a way to reach the config, and a
/// visible health state. There is no preferences window; the config file is the
/// UI.
final class MenuBar: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let engine: Engine
    private var healthTimer: Timer?

    init(engine: Engine) {
        self.engine = engine
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "copy-on-select"
        statusItem = item

        let menu = NSMenu()
        // Rebuilt only when the user opens it, rather than on a timer.
        menu.delegate = self
        item.menu = menu

        updateButton()
        // The icon is the only always-visible signal, so it alone is polled.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateButton()
        }
    }

    /// Menu bar icon point size, tuned by eye against neighbouring status
    /// items.
    private static let iconPointSize: CGFloat = 13.6

    /// Points to shift the icon downwards. The status item centres the image in
    /// its button, so the shift is achieved by padding the canvas rather than
    /// by moving the drawing.
    private static let iconDropPoints: CGFloat = 2

    /// Returns the image inside a taller transparent canvas, with the glyph
    /// held at the bottom. Once centred by the status item, the extra headroom
    /// leaves the glyph sitting `iconDropPoints` lower.
    private static func nudgedDown(_ image: NSImage) -> NSImage {
        let base = image.size
        guard base.width > 0, base.height > 0 else { return image }
        let padded = NSSize(width: base.width, height: base.height + iconDropPoints * 2)
        let result = NSImage(size: padded, flipped: false) { _ in
            image.draw(in: NSRect(x: 0, y: 0, width: base.width, height: base.height))
            return true
        }
        result.isTemplate = true
        return result
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let name: String
        if !engine.isHealthy {
            name = "exclamationmark.triangle"
        } else if engine.isEnabled {
            name = "doc.on.doc"
        } else {
            name = "pause.circle"
        }

        // SF Symbols rather than a text glyph. A glyph set as `title` aligns on
        // its baseline, which is why the old icon sat visibly too high; an
        // image is centred in the status item automatically. Template mode lets
        // it follow light/dark menu bars.
        let config = NSImage.SymbolConfiguration(
            pointSize: Self.iconPointSize, weight: .regular)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "copy-on-select")?
            .withSymbolConfiguration(config)
        {
            image.isTemplate = true
            button.image = Self.nudgedDown(image)
            button.title = ""
        } else {
            // Older systems without the symbol: fall back to the glyph.
            button.image = nil
            button.title = engine.isHealthy ? (engine.isEnabled ? "⧉" : "◌") : "⚠"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        updateButton()

        let statusText: String
        if !AX.isTrusted {
            statusText = "Accessibility not granted"
        } else if !engine.isEnabled {
            statusText = "Paused"
        } else if !engine.isTapActive {
            statusText = "Event tap inactive"
        } else {
            statusText = "Active"
        }

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: engine.isEnabled ? "Pause" : "Resume",
            action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let openConfig = NSMenuItem(
            title: "Reveal Config…", action: #selector(revealConfig), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        engine.setEnabled(!engine.isEnabled)
        updateButton()
    }

    /// Writes a default config file if none exists, then reveals it. This is
    /// the only file this app ever writes, and it never contains selection or
    /// clipboard content.
    @objc private func revealConfig() {
        let url = Config.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(Config.default) {
                try? data.write(to: url)
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
