import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class HoldPaste {
    enum Handling { case ordinary, swallow, finished }
    private let config: Config
    private let queue = DispatchQueue(label: "dev.copy-on-select.paste", qos: .userInitiated)
    private var gesture = HoldPasteGesture()
    private var timer: DispatchWorkItem?
    private lazy var button = PasteButton()
    private var target: Target?
    private var clipboardCount = -1
    private var frontmostObserver: NSObjectProtocol?
    var didActivate: (() -> Void)?

    private struct Target {
        let element: AXUIElement
        let pid: pid_t
        let range: CFRange?
    }

    init(config: Config) {
        self.config = config
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    deinit {
        if let frontmostObserver { NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver) }
    }

    func cancel() {
        timer?.cancel()
        timer = nil
        gesture.cancel()
        target = nil
        button.hide()
    }

    /// Main thread. No AX IPC or blocking work is performed in the event tap.
    func handle(_ type: CGEventType, _ event: CGEvent, enabled: Bool) -> Handling {
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        switch type {
        case .leftMouseDown:
            cancel()
            gesture.begin(at: event.location, eligible: enabled && modifiers.isEmpty
                          && event.getIntegerValueField(.mouseEventClickState) == 1)
            guard gesture.phase == .waiting else { return .ordinary }
            let token = gesture.token
            let point = gesture.origin
            let work = DispatchWorkItem { [weak self] in self?.resolve(point, token: token) }
            timer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return .ordinary
        case .leftMouseDragged:
            if !modifiers.isEmpty { cancel() }
            let consumed = gesture.move(to: event.location)
            if gesture.phase == .showing { button.track(event.location) }
            return consumed ? .swallow : .ordinary
        case .leftMouseUp:
            timer?.cancel()
            timer = nil
            let savedTarget = target
            let count = clipboardCount
            let result = gesture.release(at: event.location, allowed: enabled && modifiers.isEmpty)
            let token = gesture.token
            button.hide()
            target = nil
            switch result {
            case .ordinary: return .ordinary
            case .cancel(let origin), .paste(let origin):
                // Deliver the up to the host at its initial caret, not over
                // the overlay. Its original down/up remain balanced, and the
                // slide cannot extend the selection or start a copy gesture.
                event.location = origin
                event.setIntegerValueField(.mouseEventDeltaX, value: 0)
                event.setIntegerValueField(.mouseEventDeltaY, value: 0)
                if case .paste = result, let savedTarget {
                    // Let the native mouse-up finish before validating focus
                    // and sending Cmd+V to that same process.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.paste(savedTarget, clipboardCount: count, token: token)
                    }
                }
                return .finished
            }
        case .rightMouseDown, .otherMouseDown, .scrollWheel:
            cancel()
            return .ordinary
        default: return .ordinary
        }
    }

    private func resolve(_ point: CGPoint, token: Int) {
        guard gesture.token == token, gesture.phase == .waiting else { return }
        // Query only on a deliberate hold, not on every click or idle timer.
        let count = NSPasteboard.general.changeCount
        guard !(NSPasteboard.general.types ?? []).isEmpty else { return }
        queue.async { [weak self] in
            guard let self, let target = self.findTarget(at: point) else { return }
            DispatchQueue.main.async {
                guard self.gesture.token == token, self.gesture.phase == .waiting,
                      NSPasteboard.general.changeCount == count,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                      CGEventSource.buttonState(.combinedSessionState, button: .left),
                      let frame = self.button.prepare(near: point),
                      self.gesture.show(frame, token: token) else { return }
                self.target = target
                self.clipboardCount = count
                self.didActivate?()
                self.button.show()
                DebugTrace.log("paste menu shown")
            }
        }
    }

    private func findTarget(at point: CGPoint) -> Target? {
        guard !IsSecureEventInputEnabled(), let hit = AX.element(at: point),
              let pid = AX.pid(of: hit),
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              !config.excludedBundleIDs.contains(bundleID),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        AX.enableManualAccessibilityIfNeeded(pid: pid)
        guard let focused = AX.focusedElement(), AX.pid(of: focused) == pid,
              Self.editable(focused) else { return nil }
        // Require the hit-tested node to be the focused field or its child.
        // A field focused elsewhere does not make arbitrary screen areas safe.
        var node: AXUIElement? = hit
        for _ in 0..<config.maxAncestorWalk {
            guard let current = node, !AX.isSecure(current) else { return nil }
            if CFEqual(current, focused) {
                let range = AX.selectedRange(focused)
                // Holding selected text is a native text-drag gesture.
                guard range == nil || range?.length == 0 else { return nil }
                return Target(element: focused, pid: pid, range: range)
            }
            node = AX.parent(current)
        }
        return nil
    }

    private static func editable(_ element: AXUIElement) -> Bool {
        guard !AX.isSecure(element), let role = AX.role(element),
              ["AXTextField", "AXTextArea", "AXComboBox"].contains(role),
              (AX.attribute(element, kAXEnabledAttribute as String) as? Bool) != false
        else { return false }
        var settable = DarwinBoolean(false)
        return (AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
                && settable.boolValue) || (AX.attribute(element, "AXEditable") as? Bool) == true
    }

    private func paste(_ target: Target, clipboardCount count: Int, token: Int) {
        guard gesture.token == token else { return }
        queue.async { [weak self] in
            guard let self, !IsSecureEventInputEnabled(),
                  let focused = AX.focusedElement(), CFEqual(focused, target.element),
                  Self.editable(focused) else { return }
            // Do not paste after the insertion point or selection changed.
            if let expected = target.range {
                guard let actual = AX.selectedRange(focused), actual.location == expected.location,
                      actual.length == expected.length else { return }
            }
            DispatchQueue.main.async {
                guard self.gesture.token == token,
                      NSPasteboard.general.changeCount == count,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                      !IsSecureEventInputEnabled(),
                      CGEventSource.flagsState(.combinedSessionState)
                        .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
                      let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
                else { return }
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(target.pid)
                up.postToPid(target.pid)
                DebugTrace.log("paste shortcut sent")
            }
        }
    }
}
