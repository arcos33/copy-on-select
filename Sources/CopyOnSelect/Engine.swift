import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Turns mouse events into clipboard writes.
///
/// Ordering matters and is the whole safety argument:
///
///   1. Classify the gesture (drag / multi-click / shift-click).
///   2. Settle, so the target app has finished updating its AX state.
///   3. Resolve the target app from the EVENT's pid, not the frontmost app.
///   4. Ask accessibility what is selected, starting from the element that was
///      actually clicked.
///   5. Only synthesize Cmd+C when we know we are in a text element whose
///      selection could not be read.
///
/// Step 4 is what separates this from "fire Cmd+C on every drag": we ask rather
/// than guess, so a Finder file drag or a canvas drag produces nothing instead
/// of clobbering the clipboard.
final class Engine {
    private let queue = DispatchQueue(label: "dev.copy-on-select.engine", qos: .userInitiated)
    private var config: Config
    private var tap: EventTap?
    private var pending: DispatchWorkItem?

    // Gesture state, only touched from the event-tap callback (main run loop).
    private var downLocation: CGPoint = .zero
    private var downPID: pid_t = 0

    // Freshness state, only touched on `queue`.
    private var lastSelectionKey: String?

    private(set) var isEnabled = true

    init(config: Config) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Starts the tap. Returns false when accessibility trust is missing.
    @discardableResult
    func start() -> Bool {
        let tap = EventTap { [weak self] type, event in
            self?.handle(type: type, event: event)
        }
        guard tap.start() else { return false }
        self.tap = tap
        return true
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    var isTapActive: Bool { tap?.isActive ?? false }

    /// Accessibility can be revoked while we run. Surfacing that is better than
    /// appearing alive but doing nothing.
    var isHealthy: Bool { AX.isTrusted && isTapActive }

    // MARK: - Event handling (runs on the main run loop; must stay trivial)

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            downLocation = event.location
            downPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))

        case .leftMouseUp:
            guard isEnabled else { return }
            let up = event.location
            let clickCount = event.getIntegerValueField(.mouseEventClickState)
            let shiftHeld = event.flags.contains(.maskShift)
            let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))

            guard isSelectionCandidate(
                down: downLocation, up: up, clickCount: clickCount, shiftHeld: shiftHeld)
            else { return }

            schedule(at: downLocation, pid: pid == 0 ? downPID : pid)

        default:
            break
        }
    }

    /// A gesture is a candidate when it plausibly changed a text selection.
    ///
    /// Shift-click must be handled explicitly: it extends a selection without
    /// moving the mouse, so the drag test alone misses it and "extend the
    /// selection" appears broken.
    private func isSelectionCandidate(
        down: CGPoint, up: CGPoint, clickCount: Int64, shiftHeld: Bool
    ) -> Bool {
        let dx = up.x - down.x
        let dy = up.y - down.y
        let dragged = (dx * dx + dy * dy).squareRoot() > config.dragThreshold
        return dragged || clickCount >= 2 || shiftHeld
    }

    private func schedule(at point: CGPoint, pid: pid_t) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.resolveSelection(at: point, pid: pid)
        }
        pending = work
        queue.asyncAfter(
            deadline: .now() + .milliseconds(config.settleMilliseconds), execute: work)
    }

    // MARK: - Selection resolution (runs on `queue`, never on the tap callback)

    private func resolveSelection(at point: CGPoint, pid: pid_t) {
        guard !isExcluded(pid: pid) else { return }

        // Rung 1: the element that was actually clicked. Starting here (rather
        // than from the focused element) is what makes the result attributable
        // to this gesture instead of to whatever is selected elsewhere.
        guard let clicked = AX.element(at: point) else {
            // No AX element at all under the cursor. We cannot tell whether a
            // selection happened, so we do nothing. Guessing here is exactly
            // what produces wrong-clipboard bugs.
            return
        }

        // Never read a password field. Secure Input Mode does not cover this
        // path, so this check is the actual protection.
        if AX.isSecure(clicked) { return }

        guard AX.isTextRole(clicked) else {
            // Finder rows, canvases, title bars, sliders, scrollbars. Dropping
            // here is what prevents the file-copy and stale-copy hazards.
            return
        }

        let range = AX.selectedRange(clicked)

        if let text = AX.selectedText(clicked), !text.isEmpty {
            commit(text, pid: pid, range: range)
            return
        }

        // Rung 2: some apps expose the range plus the parameterized
        // string-for-range attribute without exposing kAXSelectedText.
        if let range, range.length > 0,
            let text = AX.string(clicked, forRange: range), !text.isEmpty
        {
            commit(text, pid: pid, range: range)
            return
        }

        // Rung 3 (gated fallback): we know this is a non-secure text element
        // whose selection is unreadable. Only now is synthesizing Cmd+C
        // justified.
        guard config.enableCopyFallback else { return }
        copyFallback(pid: pid)
    }

    private func isExcluded(pid: pid_t) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            // Unknown app: treat as excluded. Failing closed is right here.
            return true
        }
        return config.excludedBundleIDs.contains(bundleID)
    }

    /// Rejects selections we have already copied, so an unchanged selection is
    /// not rewritten and clipboard history stays clean.
    private func isFresh(pid: pid_t, range: CFRange?, text: String) -> Bool {
        let key: String
        if let range {
            key = "\(pid):\(range.location):\(range.length):\(text.count)"
        } else {
            key = "\(pid):-:-:\(text.hashValue)"
        }
        guard key != lastSelectionKey else { return false }
        lastSelectionKey = key
        return true
    }

    private func commit(_ text: String, pid: pid_t, range: CFRange?) {
        guard text.count <= config.maxCharacters else { return }
        guard isFresh(pid: pid, range: range, text: text) else { return }
        DispatchQueue.main.async {
            Clipboard.write(text, concealed: true)
        }
    }

    // MARK: - Cmd+C fallback

    /// Synthesizes Cmd+C, then restores the previous clipboard if it did not
    /// produce usable text.
    ///
    /// The save/restore is mandatory: on this path the pasteboard is overwritten
    /// before we can inspect the result, so "skip if unchanged" cannot work the
    /// way it does on the accessibility path.
    private func copyFallback(pid: pid_t) {
        let snapshot = Clipboard.snapshot()

        // Extending a selection means Shift is often physically held. Posting
        // Cmd+C now could be received as Cmd+Shift+C, a different shortcut, so
        // wait briefly for modifiers to clear. Read the state rather than
        // tapping keyboard events.
        waitForModifiersToClear(timeout: 0.6)

        postCommandC()

        // Give the target app a moment to service the keystroke.
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if NSPasteboard.general.changeCount != snapshot.changeCount { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let produced = NSPasteboard.general.string(forType: .string)
        let usable = (produced?.isEmpty == false)
            && produced!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        if NSPasteboard.general.changeCount == snapshot.changeCount || !usable {
            DispatchQueue.main.async { Clipboard.restore(snapshot) }
            return
        }

        if let produced {
            _ = isFresh(pid: pid, range: nil, text: produced)
        }
    }

    private func waitForModifiersToClear(timeout: TimeInterval) {
        let interesting: CGEventFlags = [.maskShift, .maskCommand, .maskControl, .maskAlternate]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(interesting).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func postCommandC() {
        let virtualKeyC: CGKeyCode = 0x08
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyC, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyC, keyDown: false)
        else { return }
        // Set flags explicitly so held modifiers cannot turn this into a
        // different shortcut.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
