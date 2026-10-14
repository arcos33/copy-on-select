import AppKit
import Foundation

/// A short, unobtrusive confirmation shown only after CopyOnSelect has accepted
/// a selection. This is an in-app overlay, not a Notification Center alert, so
/// it never requests notification permission or leaves a history behind.
final class CopyToast {
    static let shared = CopyToast()

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    private init() {}

    func show() {
        precondition(Thread.isMainThread)

        dismissWork?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 48))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let dismiss = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
        dismissWork = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: dismiss)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 368, height: 136),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let background = CopyToastBackgroundView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 68
        background.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "Copied")
        label.font = .systemFont(ofSize: 48, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        return panel
    }
}

private final class CopyToastBackgroundView: NSView {
    private let gradient = NSGradient(
        starting: NSColor(srgbRed: 0, green: 100.0 / 255, blue: 230.0 / 255, alpha: 1),
        ending: NSColor(srgbRed: 45.0 / 255, green: 146.0 / 255, blue: 1, alpha: 1))

    override func draw(_ dirtyRect: NSRect) {
        // AppKit's unflipped coordinates run upward: deeper blue below, lighter above.
        gradient?.draw(in: bounds, angle: 90)
    }
}
