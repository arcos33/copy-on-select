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

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        if !engine.isHealthy {
            button.title = "⚠"
        } else if engine.isEnabled {
            button.title = "⧉"
        } else {
            // A combining slash renders unreliably in the menu bar; use a
            // distinct glyph instead.
            button.title = "◌"
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
