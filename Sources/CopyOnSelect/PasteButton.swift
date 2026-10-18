import AppKit

/// Nonactivating and mouse-transparent: the event tap owns the held gesture,
/// and the destination field retains keyboard focus throughout.
final class PasteButton {
    private let panel: NSPanel
    private let face: PasteButtonFace
    private var quartzFrame = CGRect.zero

    init() {
        face = PasteButtonFace(frame: NSRect(x: 0, y: 0, width: 124, height: 48))
        panel = NSPanel(contentRect: face.bounds, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = face
    }

    static func frame(near point: CGPoint, in screen: CGRect) -> CGRect {
        // Deliberate gap: a stationary release must never accidentally paste.
        let size = CGSize(width: 124, height: 48)
        var x = point.x + 18
        if x + size.width > screen.maxX - 8 { x = point.x - 18 - size.width }
        let y = min(max(point.y - size.height / 2, screen.minY + 8), screen.maxY - size.height - 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    func prepare(near point: CGPoint) -> CGRect? {
        // Quartz uses top-left of the PRIMARY display; AppKit uses bottom-left.
        // NSScreen.main can change with focus and must not be used as the origin.
        guard let primary = NSScreen.screens.first else { return nil }
        let top = primary.frame.maxY
        let appPoint = NSPoint(x: point.x, y: top - point.y)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appPoint) }) else { return nil }
        let visible = screen.visibleFrame
        let quartzScreen = CGRect(x: visible.minX, y: top - visible.maxY,
                                  width: visible.width, height: visible.height)
        quartzFrame = Self.frame(near: point, in: quartzScreen)
        panel.setFrame(NSRect(x: quartzFrame.minX, y: top - quartzFrame.maxY,
                              width: quartzFrame.width, height: quartzFrame.height), display: false)
        face.highlighted = false
        return quartzFrame
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func track(_ point: CGPoint) { face.highlighted = quartzFrame.contains(point) }
}

private final class PasteButtonFace: NSView {
    var highlighted = false { didSet { if oldValue != highlighted { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Paste")
        setAccessibilityHelp("Slide here and release to paste. Release outside to cancel.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        (highlighted ? NSColor.selectedContentBackgroundColor : NSColor.windowBackgroundColor).setFill()
        shape.fill()
        (highlighted ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = highlighted ? 2 : 1
        shape.stroke()
        let color: NSColor = highlighted ? .alternateSelectedControlTextColor : .labelColor
        let text = NSAttributedString(string: "Paste", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: color,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
