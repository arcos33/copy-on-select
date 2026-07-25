import AppKit
import Foundation

/// Minimal status-bar item: an off switch, a way to reach the config, and a
/// visible health state. There is no preferences window; the config file is the
/// UI.
final class MenuBar: NSObject {
    private var statusItem: NSStatusItem?
    private let engine: Engine
    private var healthTimer: Timer?

    init(engine: Engine) {
        self.engine = engine
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⧉"
        item.button?.toolTip = "copy-on-select"
        statusItem = item
        rebuildMenu()

        // Accessibility can be revoked, and a tap can die. Showing that beats
        // looking alive while doing nothing.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let healthy = engine.isHealthy
        statusItem.button?.title = healthy ? (engine.isEnabled ? "⧉" : "⧉̸") : "⚠"

        let status = NSMenuItem(
            title: healthy
                ? (engine.isEnabled ? "Active" : "Paused")
                : (AX.isTrusted ? "Event tap inactive" : "Accessibility not granted"),
            action: nil, keyEquivalent: "")
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

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        engine.setEnabled(!engine.isEnabled)
        rebuildMenu()
    }

    @objc private func revealConfig() {
        let url = Config.fileURL
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
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
